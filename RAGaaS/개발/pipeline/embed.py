# -*- coding: utf-8 -*-
"""임베딩 — 청크를 벡터로 바꾼다.

두 개의 백엔드를 제공한다. 목적이 다르다.

  ① azure     Azure OpenAI text-embedding-3-large 호출 (운영용)
              실제 의미 벡터를 만든다. 자격 증명과 비용이 필요하다.

  ② local-lsa TF-IDF + SVD 로 만드는 잠재의미 벡터 (오프라인 검증용)
              Azure 없이도 파이프라인 전체를 돌려 «RRF 가 실제로 어떻게 동작하는지»를
              눈으로 확인할 수 있다.

⚠️ local-lsa 를 «임베딩 모델의 대용»으로 오해하면 안 된다.
   LSA 는 문서 집합 안의 단어 공기(共起)만 본다. 학습 코퍼스의 세계 지식이 없으므로
   «육아휴직 ↔ 출산 후 쉬는 제도» 같은 외부 지식 기반 유사도는 잡지 못한다.
   그럼에도 유용한 이유는, 파이프라인의 «배관»(청크 → 벡터 → 검색 → 융합)이
   제대로 이어졌는지는 벡터의 품질과 무관하게 검증할 수 있기 때문이다.
   품질 판정은 반드시 azure 백엔드로 다시 해야 한다.

사용:
    python embed.py --backend local-lsa --dim 256
    python embed.py --backend azure --model text-embedding-3-large --dim 1536
    python embed.py --estimate-only          # 비용만 계산하고 끝낸다
"""
import argparse
import io
import json
import math
import os
import re
import sys

# stdout 을 «한 번만» UTF-8 로 감싼다.
# 이미 UTF-8 이면 건드리지 않는다 — 이중 래핑하면 안쪽 래퍼가 수거될 때
# 하위 버퍼가 닫혀 «I/O operation on closed file» 이 난다.
if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# ═══════════════════════════════════════════════════════════ 토큰 추정
#
# tiktoken 이 없는 환경에서도 비용을 추정할 수 있어야 한다.
# 정확한 토큰 수는 모델 토크나이저만 알지만, «주문 전에 대략의 청구서»는 알아야 하기 때문이다.

# cl100k_base 기준 경험값.
#   한글은 음절당 약 1.5 토큰 (자모 분해되지 않고 음절 단위로 잡히나 다바이트라 분할됨)
#   영문·숫자는 4자당 약 1 토큰
#   공백·기호는 거의 무시 가능
KO_TOKENS_PER_CHAR = 1.5
EN_CHARS_PER_TOKEN = 4.0

_KO = re.compile(r"[가-힣]")
_EN = re.compile(r"[A-Za-z0-9]")


def estimate_tokens(text):
    """토큰 수 추정.

    ⚠️ 추정이다. 실제 청구는 Azure OpenAI 가 반환하는 usage 값을 따른다.
       tiktoken 이 설치되어 있으면 그것을 쓴다.
    """
    try:
        import tiktoken
        return len(tiktoken.get_encoding("cl100k_base").encode(text))
    except Exception:
        ko = len(_KO.findall(text))
        en = len(_EN.findall(text))
        other = len(text) - ko - en
        return int(ko * KO_TOKENS_PER_CHAR + en / EN_CHARS_PER_TOKEN + other * 0.3)


# ═══════════════════════════════════════════════════════════ 모델 제원
#
# ⚠️ 단가는 «확인이 필요한 값»이다. 지역·계약·시점에 따라 다르다.
#    아래 값은 계산 «구조»를 보여 주기 위한 자리표시자이며,
#    실제 예산 수립 전에 Azure 가격 페이지에서 반드시 확인해야 한다.
MODELS = {
    "text-embedding-3-large": {
        "기본차원": 3072,
        "축소가능": True,
        "최대입력토큰": 8191,
        "단가_USD_per_1M": None,   # ← 확인 필요. 임의로 채우면 예산이 틀어진다
        "비고": "차원 축소(MRL) 지원. 1536·1024·256 등으로 줄여도 품질 저하가 작다",
    },
    "text-embedding-3-small": {
        "기본차원": 1536,
        "축소가능": True,
        "최대입력토큰": 8191,
        "단가_USD_per_1M": None,
        "비고": "large 대비 저렴. 한국어 품질은 반드시 직접 비교할 것",
    },
    "text-embedding-ada-002": {
        "기본차원": 1536,
        "축소가능": False,
        "최대입력토큰": 8191,
        "단가_USD_per_1M": None,
        "비고": "구세대. 신규 구축에는 권장하지 않음",
    },
}


# ═══════════════════════════════════════════════════════════ 로컬 LSA 백엔드

def build_local_lsa(texts, dim=256, min_df=3, max_df_ratio=0.5):
    """TF-IDF → SVD 로 잠재의미 벡터를 만든다.

    numpy 만으로 구현한다. scikit-learn 이 없는 환경에서도 돌아야 하기 때문이다.

    Returns:
        (vectors, vocab, idf, components) — 쿼리도 같은 공간으로 투영해야 하므로
        어휘·IDF·성분을 함께 돌려준다.
    """
    import numpy as np

    # ── 토큰화: 한글은 2-gram, 영숫자는 단어 단위
    #    한국어는 교착어라 어절 그대로 쓰면 «연차휴가를»과 «연차휴가는»이 다른 토큰이 된다.
    #    형태소 분석기가 없는 환경에서는 문자 n-gram 이 실용적인 절충안이다.
    def tokenize(t):
        toks = re.findall(r"[A-Za-z0-9]+", t.lower())
        ko = "".join(_KO.findall(t))
        toks += [ko[i:i + 2] for i in range(len(ko) - 1)]
        return toks

    print("  토큰화 중…")
    docs_tokens = [tokenize(t) for t in texts]

    # ── 어휘 구축 (문서 빈도 기준 필터)
    df = {}
    for toks in docs_tokens:
        for t in set(toks):
            df[t] = df.get(t, 0) + 1
    n_docs = len(texts)
    max_df = int(n_docs * max_df_ratio)
    vocab = {t: i for i, (t, c) in enumerate(
        sorted(((t, c) for t, c in df.items() if min_df <= c <= max_df),
               key=lambda kv: -kv[1]))}
    print(f"  어휘 {len(vocab):,}개 (문서빈도 {min_df} ~ {max_df:,})")

    if not vocab:
        raise RuntimeError("어휘가 비었습니다. min_df 를 낮추세요.")

    idf = np.zeros(len(vocab), dtype=np.float32)
    for t, i in vocab.items():
        idf[i] = math.log((n_docs + 1) / (df[t] + 1)) + 1.0

    # ── TF-IDF 희소 행렬 (밀집으로 만들면 메모리가 터진다)
    print("  TF-IDF 행렬 구성 중…")
    rows, cols, vals = [], [], []
    for r, toks in enumerate(docs_tokens):
        tf = {}
        for t in toks:
            j = vocab.get(t)
            if j is not None:
                tf[j] = tf.get(j, 0) + 1
        if not tf:
            continue
        norm = math.sqrt(sum((1 + math.log(c)) ** 2 * idf[j] ** 2 for j, c in tf.items()))
        if norm == 0:
            continue
        for j, c in tf.items():
            rows.append(r)
            cols.append(j)
            vals.append((1 + math.log(c)) * idf[j] / norm)

    # ── 무작위 투영 기반 SVD (전체 SVD 는 이 크기에서 비현실적)
    #    Halko 등의 randomized SVD 를 간략화한 형태.
    print(f"  SVD {dim}차원으로 축소 중…")
    rng = np.random.default_rng(20260829)
    n_vocab = len(vocab)
    omega = rng.standard_normal((n_vocab, dim + 10), dtype=np.float32)

    rows_a = np.array(rows, dtype=np.int64)
    cols_a = np.array(cols, dtype=np.int64)
    vals_a = np.array(vals, dtype=np.float32)

    # Y = A @ omega   (희소 행렬 곱을 인덱스 누적으로 수행)
    y = np.zeros((n_docs, dim + 10), dtype=np.float32)
    np.add.at(y, rows_a, vals_a[:, None] * omega[cols_a])

    # QR 로 직교 기저를 얻는다
    q, _ = np.linalg.qr(y)

    # B = Q.T @ A  → (dim+10, n_vocab)
    b = np.zeros((q.shape[1], n_vocab), dtype=np.float32)
    np.add.at(b.T, cols_a, vals_a[:, None] * q[rows_a])

    ub, sb, vtb = np.linalg.svd(b, full_matrices=False)
    components = vtb[:dim]                     # (dim, n_vocab)

    # 문서 벡터 = A @ components.T
    vectors = np.zeros((n_docs, dim), dtype=np.float32)
    np.add.at(vectors, rows_a, vals_a[:, None] * components.T[cols_a])

    # 코사인 유사도를 쓰려면 정규화해야 한다
    norms = np.linalg.norm(vectors, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    vectors = vectors / norms

    return vectors, vocab, idf, components


def embed_query_local(text, vocab, idf, components):
    """쿼리를 문서와 «같은 공간»으로 투영한다.

    ⚠️ 문서와 다른 방식으로 벡터를 만들면 유사도가 무의미해진다.
       토큰화·IDF·성분을 그대로 재사용해야 한다.
    """
    import numpy as np

    toks = re.findall(r"[A-Za-z0-9]+", text.lower())
    ko = "".join(_KO.findall(text))
    toks += [ko[i:i + 2] for i in range(len(ko) - 1)]

    tf = {}
    for t in toks:
        j = vocab.get(t)
        if j is not None:
            tf[j] = tf.get(j, 0) + 1
    if not tf:
        return np.zeros(components.shape[0], dtype=np.float32)

    norm = math.sqrt(sum((1 + math.log(c)) ** 2 * idf[j] ** 2 for j, c in tf.items()))
    v = np.zeros(components.shape[0], dtype=np.float32)
    for j, c in tf.items():
        v += (1 + math.log(c)) * idf[j] / norm * components[:, j]

    n = np.linalg.norm(v)
    return v / n if n else v


# ═══════════════════════════════════════════════════════════ Azure 백엔드

def embed_azure(texts, model, dim, batch=64):
    """Azure OpenAI 임베딩 호출.

    자격 증명은 «환경 변수»로만 받는다. 코드나 파일에 두지 않는다.
      AZURE_OPENAI_ENDPOINT      https://<리소스>.openai.azure.com
      AZURE_OPENAI_DEPLOYMENT    임베딩 배포 이름
      (인증) DefaultAzureCredential — 관리 ID / az login

    ⚠️ 이 함수는 실제로 과금된다. 청크 1만 건이면 수십만 토큰이 소모된다.
       먼저 --estimate-only 로 규모를 확인하고 실행할 것.
    """
    try:
        from azure.identity import DefaultAzureCredential, get_bearer_token_provider
        from openai import AzureOpenAI
    except ImportError as e:
        raise RuntimeError(
            "azure-identity 와 openai 패키지가 필요합니다.\n"
            "  pip install azure-identity openai\n"
            f"  (원인: {e})"
        )

    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
    deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT", model)
    if not endpoint:
        raise RuntimeError("AZURE_OPENAI_ENDPOINT 환경 변수가 필요합니다.")

    # ★ API 키를 쓰지 않는다. 관리 ID / 개발자 계정 토큰으로 인증한다.
    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(),
        "https://cognitiveservices.azure.com/.default",
    )
    client = AzureOpenAI(
        azure_endpoint=endpoint,
        azure_ad_token_provider=token_provider,
        api_version="2024-10-21",
    )

    out, used_tokens = [], 0
    for i in range(0, len(texts), batch):
        part = texts[i:i + batch]
        kwargs = {"input": part, "model": deployment}
        if dim and MODELS.get(model, {}).get("축소가능"):
            kwargs["dimensions"] = dim
        resp = client.embeddings.create(**kwargs)
        out.extend(d.embedding for d in resp.data)
        used_tokens += resp.usage.total_tokens
        print(f"    {min(i + batch, len(texts)):,}/{len(texts):,} "
              f"(누적 {used_tokens:,} 토큰)", end="\r")
    print()
    return out, used_tokens


# ═══════════════════════════════════════════════════════════ 실행

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="청크 임베딩")
    ap.add_argument("--in", dest="src",
                    default=os.path.join(here, "..", "data", "chunks.jsonl"))
    ap.add_argument("--out", dest="dst",
                    default=os.path.join(here, "..", "data", "vectors.npz"))
    ap.add_argument("--backend", choices=["local-lsa", "azure"], default="local-lsa")
    ap.add_argument("--model", default="text-embedding-3-large")
    ap.add_argument("--dim", type=int, default=256,
                    help="local-lsa 는 256 권장. azure 는 1536 또는 3072")
    ap.add_argument("--estimate-only", action="store_true",
                    help="비용만 추정하고 임베딩은 하지 않는다")
    ap.add_argument("--limit", type=int, default=0, help="앞에서 N건만 (실험용)")
    args = ap.parse_args()

    src = os.path.abspath(args.src)
    chunks = []
    with io.open(src, encoding="utf-8") as f:
        for line in f:
            chunks.append(json.loads(line))
    if args.limit:
        chunks = chunks[:args.limit]

    texts = [c["content"] for c in chunks]

    print("=" * 68)
    print(" 임베딩")
    print("=" * 68)
    print(f" 청크 {len(chunks):,}건 · 백엔드 {args.backend}")
    print()

    # ── 토큰·비용 추정
    print(" 토큰 추정 중…")
    tokens = [estimate_tokens(t) for t in texts]
    total_tokens = sum(tokens)
    tokens_sorted = sorted(tokens)
    spec = MODELS.get(args.model, {})
    over_limit = [i for i, t in enumerate(tokens) if t > spec.get("최대입력토큰", 8191)]

    try:
        import tiktoken  # noqa: F401
        method = "tiktoken (정확)"
    except ImportError:
        method = "문자 기반 추정 (±20% 오차 가능)"

    print()
    print(f" 총 토큰      {total_tokens:>12,}   ({method})")
    print(f" 청크당 평균  {total_tokens // len(tokens):>12,}")
    print(f" 청크당 최대  {tokens_sorted[-1]:>12,}   "
          f"(모델 한계 {spec.get('최대입력토큰', '?'):,})")
    print(f" 한계 초과    {len(over_limit):>12,}건")

    unit = spec.get("단가_USD_per_1M")
    if unit:
        print(f" 예상 비용    {total_tokens / 1_000_000 * unit:>12,.2f} USD")
    else:
        print()
        print(" ⚠️ 단가가 «확인 필요» 상태입니다.")
        print("    지역·계약·시점에 따라 다르므로 임의의 값을 넣지 않았습니다.")
        print("    Azure OpenAI 가격 페이지에서 확인한 뒤 MODELS 에 채우세요.")
        print(f"    계산식: {total_tokens:,} 토큰 ÷ 1,000,000 × 단가(USD/1M)")

    estimate = {
        "청크수": len(chunks),
        "총토큰_추정": total_tokens,
        "추정방법": method,
        "청크당토큰": {
            "최소": tokens_sorted[0], "최대": tokens_sorted[-1],
            "중앙값": tokens_sorted[len(tokens_sorted) // 2],
            "평균": total_tokens // len(tokens),
            "p99": tokens_sorted[int(len(tokens_sorted) * 0.99)],
        },
        "모델": args.model,
        "모델제원": spec,
        "한계초과청크": len(over_limit),
        "주의": "단가는 확인이 필요한 값이다. 여기에 임의 값을 넣으면 예산이 틀어진다.",
    }
    est_path = os.path.join(os.path.dirname(os.path.abspath(args.dst)),
                            "embed_estimate.json")
    with io.open(est_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(estimate, f, ensure_ascii=False, indent=2)
    print()
    print(f"  → {est_path}")

    if args.estimate_only:
        print()
        print(" (--estimate-only) 임베딩은 수행하지 않았습니다.")
        return 0

    # ── 임베딩 수행
    import numpy as np
    print()
    if args.backend == "azure":
        print(" Azure OpenAI 호출 — ⚠️ 실제 과금됩니다")
        vecs, used = embed_azure(texts, args.model, args.dim)
        vectors = np.array(vecs, dtype=np.float32)
        # 코사인 유사도용 정규화
        norms = np.linalg.norm(vectors, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        vectors = vectors / norms
        aux = {"backend": "azure", "model": args.model, "used_tokens": used}
        np.savez_compressed(os.path.abspath(args.dst), vectors=vectors,
                            chunk_ids=np.array([c["chunk_id"] for c in chunks]))
    else:
        print(" 로컬 LSA — 오프라인 검증용 (의미 품질은 Azure 백엔드로 재확인할 것)")
        vectors, vocab, idf, components = build_local_lsa(texts, dim=args.dim)
        aux = {"backend": "local-lsa", "dim": args.dim, "vocab": len(vocab)}
        np.savez_compressed(
            os.path.abspath(args.dst),
            vectors=vectors,
            chunk_ids=np.array([c["chunk_id"] for c in chunks]),
            idf=idf,
            components=components,
            vocab_terms=np.array(list(vocab.keys())),
            vocab_index=np.array(list(vocab.values()), dtype=np.int32),
        )

    meta_path = os.path.join(os.path.dirname(os.path.abspath(args.dst)),
                             "vectors_meta.json")
    with io.open(meta_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump({**aux, "count": len(chunks), "shape": list(vectors.shape)},
                  f, ensure_ascii=False, indent=2)

    print()
    print("-" * 68)
    print(f" 벡터 {vectors.shape[0]:,} × {vectors.shape[1]}차원")
    print(f"  → {os.path.abspath(args.dst)}")
    print(f"  → {meta_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
