# -*- coding: utf-8 -*-
"""하이브리드 검색 — BM25 + 벡터 + RRF 융합.

Azure AI Search 가 내부에서 하는 일을 «같은 알고리즘으로» 재현한다.
목적은 Azure 를 대체하는 것이 아니라, 배포 전에 다음을 눈으로 확인하는 것이다.

  · 키워드만 쓸 때 무엇을 놓치는가
  · 벡터만 쓸 때 무엇을 놓치는가
  · 왜 둘을 합쳐야 하는가  ← 이것을 «설명»이 아니라 «수치»로 보여 준다

Azure 와 맞춘 부분
  · RRF 상수 k = 60          (Azure 문서에 명시된 값)
  · RRF 점수 = Σ 1/(k+rank)  (각 결과 집합에서의 순위만 쓴다. 원 점수는 쓰지 않는다)
  · 벡터 가중치(weight)      (기본 1.0. 조절하면 벡터 쪽 기여가 커지거나 작아진다)
  · BM25 k1=1.2, b=0.75      (일반적인 기본값)

Azure 와 다른 부분 — 정직하게
  · 시맨틱 랭커(L2)는 Microsoft 의 학습된 교차 인코더다. 재현할 수 없다.
    여기서는 «랭커가 붙으면 순위가 어떻게 달라지는가»를 보여 주기 위한
    간이 근사(제목 일치·용어 밀도 기반)만 제공하며, 이름도 그렇게 붙였다.
  · 실제 품질 판정은 반드시 Azure 에서 다시 해야 한다.

사용:
    python hybrid.py --q "연차휴가 며칠 쓸 수 있나요"
    python hybrid.py --q "육아휴직 급여" --mode compare
    python hybrid.py --q "출장 숙박비 한도" --filter "category=총무"
"""
import argparse
import io
import json
import math
import os
import re
import sys
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pipeline"))
# stdout 을 «한 번만» UTF-8 로 감싼다.
# 이미 UTF-8 이면 건드리지 않는다 — 이중 래핑하면 안쪽 래퍼가 수거될 때
# 하위 버퍼가 닫혀 «I/O operation on closed file» 이 난다.
if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# ═══════════════════════════════════════════════════════════ 상수

RRF_K = 60
#   Azure AI Search 가 쓰는 값. 실험적으로 60 부근이 가장 안정적이라고 알려져 있다.
#   ⚠️ 벡터 검색의 k(이웃 개수)와 «전혀 다른» 값이다. 이름만 같다.

BM25_K1 = 1.2   # 용어 빈도 포화 지점. 클수록 반복 등장의 가치가 오래 유지된다
BM25_B = 0.75   # 문서 길이 정규화 강도. 1이면 완전 정규화, 0이면 무시

_KO = re.compile(r"[가-힣]")


def tokenize(text):
    """문서·쿼리 공통 토큰화.

    ⚠️ 색인과 검색이 «같은» 토큰화를 써야 한다. 다르면 매칭이 무너진다.
       한국어는 교착어라 어절 그대로 쓰면 «연차휴가를»과 «연차휴가는»이 다른 토큰이 된다.
       형태소 분석기가 없는 환경에서는 문자 2-gram 이 실용적인 절충안이다.
       (Azure 에서는 ko.lucene 또는 ko.microsoft 분석기를 쓴다 — 형태소 기반이라 더 낫다)
    """
    toks = re.findall(r"[A-Za-z0-9]+", text.lower())
    ko = "".join(_KO.findall(text))
    toks += [ko[i:i + 2] for i in range(len(ko) - 1)]
    return toks


# ═══════════════════════════════════════════════════════════ BM25

class BM25:
    """BM25 키워드 검색.

    벡터가 못 하는 것을 한다 — «정확한 용어»와 «숫자»를 잡는다.
    «15일»과 «25일»은 의미 공간에서 거의 같은 위치에 있지만, BM25 는 다르게 본다.
    """

    def __init__(self, docs_tokens):
        self.n = len(docs_tokens)
        self.doc_len = [len(t) for t in docs_tokens]
        self.avg_len = sum(self.doc_len) / self.n if self.n else 0.0

        self.postings = defaultdict(list)      # term → [(doc_idx, tf), …]
        df = defaultdict(int)
        for i, toks in enumerate(docs_tokens):
            tf = defaultdict(int)
            for t in toks:
                tf[t] += 1
            for t, c in tf.items():
                self.postings[t].append((i, c))
                df[t] += 1

        # IDF — 흔한 용어일수록 가치가 낮다
        self.idf = {
            t: math.log(1 + (self.n - c + 0.5) / (c + 0.5))
            for t, c in df.items()
        }

    def search(self, query, top=50, allowed=None):
        """Returns: [(doc_idx, score)] 점수 내림차순."""
        scores = defaultdict(float)
        for t in tokenize(query):
            if t not in self.postings:
                continue
            idf = self.idf[t]
            for i, tf in self.postings[t]:
                if allowed is not None and i not in allowed:
                    continue
                denom = tf + BM25_K1 * (1 - BM25_B + BM25_B * self.doc_len[i] / self.avg_len)
                scores[i] += idf * (tf * (BM25_K1 + 1)) / denom
        return sorted(scores.items(), key=lambda kv: -kv[1])[:top]


# ═══════════════════════════════════════════════════════════ 벡터 검색

class VectorIndex:
    """전수 탐색 벡터 검색.

    Azure 는 HNSW(근사 최근접)를 쓴다. 1만 건 규모에서는 전수 탐색이 충분히 빠르고,
    «근사로 인한 누락»이 없어 알고리즘 비교에 오히려 적합하다.
    (Azure 에서도 exhaustive: true 로 전수 탐색을 강제할 수 있다)
    """

    def __init__(self, vectors):
        self.vectors = vectors                 # 이미 L2 정규화되어 있다

    def search(self, qvec, top=50, allowed=None):
        import numpy as np
        sims = self.vectors @ qvec             # 정규화되어 있으므로 내적 = 코사인
        if allowed is not None:
            mask = np.full(len(sims), -np.inf, dtype=np.float32)
            idx = np.fromiter(allowed, dtype=np.int64, count=len(allowed))
            mask[idx] = sims[idx]
            sims = mask
        k = min(top, len(sims))
        part = np.argpartition(-sims, k - 1)[:k]
        part = part[np.argsort(-sims[part])]
        return [(int(i), float(sims[i])) for i in part if sims[i] > -np.inf]


# ═══════════════════════════════════════════════════════════ RRF 융합

def reciprocal_rank_fusion(result_sets, k=RRF_K, weights=None):
    """상호 순위 융합.

    핵심: «원 점수»를 쓰지 않고 «순위»만 쓴다.
        BM25 점수는 상한이 없고, 코사인은 -1~1 이다. 스케일이 완전히 다르므로
        점수를 직접 더하면 한쪽이 항상 이긴다. 순위로 바꾸면 그 문제가 사라진다.

    Args:
        result_sets: [[(doc_idx, score)], …] 각각 순위순으로 정렬된 결과
        k:           RRF 상수 (Azure 는 60)
        weights:     결과 집합별 가중치. None 이면 모두 1.0

    Returns:
        [(doc_idx, rrf_score, {집합번호: 순위})] — 기여도를 함께 돌려준다.
        «왜 이 문서가 위로 왔는가»를 설명할 수 있어야 튜닝이 가능하기 때문이다.
    """
    weights = weights or [1.0] * len(result_sets)
    fused = defaultdict(float)
    contrib = defaultdict(dict)

    for set_no, (results, w) in enumerate(zip(result_sets, weights)):
        for rank, (doc_idx, _score) in enumerate(results, start=1):
            fused[doc_idx] += w * (1.0 / (k + rank))
            contrib[doc_idx][set_no] = rank

    ranked = sorted(fused.items(), key=lambda kv: -kv[1])
    return [(i, s, contrib[i]) for i, s in ranked]


# ═══════════════════════════════════════════════════════════ 간이 재순위
#
# ⚠️ 이것은 Azure 시맨틱 랭커가 «아니다».
#    Azure 의 L2 랭커는 Bing 계열 교차 인코더로, 여기서 재현할 수 없다.
#    이 함수는 «재순위 단계가 붙으면 결과가 어떻게 달라지는지»를 보여 주는 교육용 근사다.

def naive_rerank(query, candidates, chunks, top=10, idf=None):
    """IDF 가중 용어 일치 · 최신성으로 재정렬한다.

    ★ IDF 가중이 «반드시» 필요한 이유 — 없이 만들었다가 실패한 기록
      단순히 «겹치는 토큰 수»로 점수를 매기면 이런 일이 벌어진다.

        질의  "연차휴가 일수 기준이 어떻게 되나요?"
        토큰  [연차, 차휴, 휴가, 가일, 일수, 어떻, 떻게, 게되, 되나, 나요]
                                        └──────── 5개가 «질문 어투» ────────┘

      «어떻게 되나요?»로 끝나는 FAQ 제목은 이 5개를 전부 맞힌다.
      정작 답이 들어 있는 «연차휴가 일수 기준표»는 그 어투가 없어서 진다.
      → 재순위가 «답의 관련성»이 아니라 «질문 어투의 유사성»을 보상하게 된다.

      IDF 를 곱하면 «어떻»·«나요» 같은 고빈도 토큰의 가중치가 0에 수렴하고,
      «일수»·«연차» 같은 변별력 있는 토큰이 점수를 지배한다.

    Args:
        idf: 토큰 → IDF 값. None 이면 균등 가중(권장하지 않음).

    Returns: [(doc_idx, score, 근거)]
    """
    qt = list(dict.fromkeys(tokenize(query)))     # 순서 유지 중복 제거
    if idf:
        weights = {t: idf.get(t, 0.0) for t in qt}
    else:
        weights = {t: 1.0 for t in qt}
    total_w = sum(weights.values()) or 1.0

    scored = []
    for doc_idx, _rrf, _c in candidates[:max(top * 5, 50)]:
        c = chunks[doc_idx]
        ct = tokenize(c["content"])
        cts = set(ct)
        title_set = set(tokenize(c["title"]))

        matched_w = sum(w for t, w in weights.items() if t in cts)
        title_w = sum(w for t, w in weights.items() if t in title_set)

        overlap = matched_w / total_w                                # IDF 가중 재현율
        title_hit = title_w / total_w
        density = matched_w / (math.log(len(ct) + 1) + 1)            # 짧은 문서 우대

        # 최신성 — 폐지 문서는 강하게 감점한다.
        # 이것이 «버전 충돌» 함정을 푸는 열쇠다.
        status = c.get("status")
        recency = 1.0 if status == "현행" else (0.3 if status == "개정예정" else 0.05)

        score = (overlap * 2.0 + title_hit * 3.0 + density * 0.3) * recency
        scored.append((doc_idx, score, {
            "용어재현": round(overlap, 3),
            "제목일치": round(title_hit, 3),
            "밀도": round(density, 3),
            "최신성": recency,
        }))

    return sorted(scored, key=lambda x: -x[1])[:top]


# ═══════════════════════════════════════════════════════════ 필터

def parse_filter(expr):
    """«category=인사,status=현행» 형태를 dict 로."""
    if not expr:
        return {}
    out = {}
    for part in expr.split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def apply_filter(chunks, filters, security_clearance=None):
    """필터에 맞는 청크 인덱스 집합을 만든다.

    ★ 보안 등급은 «필터»가 아니라 «강제»다.
      사용자가 요청하지 않아도 항상 적용해야 한다.
      LLM 프롬프트로 «제한 문서는 보여 주지 마»라고 지시하는 것은 방어가 아니다.
      검색 단계에서 아예 제외해야 한다.
    """
    allowed = set()
    for i, c in enumerate(chunks):
        if security_clearance is not None:
            level = c.get("security_level")
            if level == "제한" and security_clearance != "제한":
                continue
            if level == "사내" and security_clearance == "공개":
                continue
        if all(str(c.get(k)) == v for k, v in filters.items()):
            allowed.add(i)
    return allowed


# ═══════════════════════════════════════════════════════════ 검색 엔진

class HybridSearch:
    def __init__(self, chunks, vectors, vocab, idf, components):
        self.chunks = chunks
        self.bm25 = BM25([tokenize(c["content"]) for c in chunks])
        self.vec = VectorIndex(vectors)
        self.vocab, self.idf, self.components = vocab, idf, components

    def _qvec(self, query):
        from embed import embed_query_local
        return embed_query_local(query, self.vocab, self.idf, self.components)

    def keyword(self, query, top=10, allowed=None):
        return self.bm25.search(query, top, allowed)

    def vector(self, query, top=10, allowed=None):
        return self.vec.search(self._qvec(query), top, allowed)

    def hybrid(self, query, top=10, allowed=None, vector_weight=1.0, recall=50):
        """BM25 와 벡터를 각각 recall 개씩 뽑아 RRF 로 융합한다.

        recall 을 top 보다 크게 잡는 이유 — 융합 «전»에 후보가 충분해야
        한쪽에서만 잡힌 문서가 살아남는다. Azure 의 maxTextRecallSize 와 같은 역할.
        """
        kw = self.bm25.search(query, recall, allowed)
        vc = self.vec.search(self._qvec(query), recall, allowed)
        fused = reciprocal_rank_fusion([kw, vc], weights=[1.0, vector_weight])
        return fused[:top], kw, vc

    def semantic(self, query, top=10, allowed=None, vector_weight=1.0, recall=50):
        """하이브리드 후 재순위. Azure 의 «하이브리드 + 시맨틱 랭커»에 대응."""
        fused, kw, vc = self.hybrid(query, top=recall, allowed=allowed,
                                    vector_weight=vector_weight, recall=recall)
        # ★ BM25 의 IDF 를 재순위에 넘긴다. 없으면 «질문 어투»가 점수를 지배한다.
        return naive_rerank(query, fused, self.chunks, top, idf=self.bm25.idf), kw, vc


# ═══════════════════════════════════════════════════════════ 출력

def show(chunks, results, label, limit=5, scored=True):
    print()
    print(f" ── {label}")
    if not results:
        print("    (결과 없음)")
        return
    for rank, item in enumerate(results[:limit], start=1):
        i = item[0]
        score = item[1] if scored else 0.0
        c = chunks[i]
        flag = ""
        if c.get("status") == "폐지":
            flag = "  ⚠️폐지"
        elif c.get("status") == "개정예정":
            flag = "  △개정예정"
        if c.get("security_level") == "제한":
            flag += "  🔒제한"
        print(f"    {rank}. [{score:.4f}] {c['title'][:52]}{flag}")
        print(f"       {c['doc_type']} · {c['category']}>{c['subcategory']} · "
              f"{c['chunk_id']}")
        body = c["content"].replace("\n", " ")[:110]
        print(f"       {body}…")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    data = os.path.join(here, "..", "data")

    ap = argparse.ArgumentParser(description="하이브리드 검색 (BM25 + 벡터 + RRF)")
    ap.add_argument("--q", required=True, help="검색어")
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--mode", choices=["hybrid", "compare", "semantic"],
                    default="compare",
                    help="compare 는 키워드/벡터/하이브리드를 나란히 보여 준다")
    ap.add_argument("--filter", default="", help="예: category=인사,status=현행")
    ap.add_argument("--clearance", choices=["공개", "사내", "제한"], default="사내",
                    help="사용자 보안 등급. 이보다 높은 문서는 제외된다")
    ap.add_argument("--vector-weight", type=float, default=1.0)
    args = ap.parse_args()

    import numpy as np

    chunks = []
    with io.open(os.path.join(data, "chunks.jsonl"), encoding="utf-8") as f:
        for line in f:
            chunks.append(json.loads(line))

    npz = np.load(os.path.join(data, "vectors.npz"), allow_pickle=False)
    vectors = npz["vectors"]
    vocab = {t: int(i) for t, i in zip(npz["vocab_terms"], npz["vocab_index"])}
    idf, components = npz["idf"], npz["components"]

    engine = HybridSearch(chunks, vectors, vocab, idf, components)

    filters = parse_filter(args.filter)
    allowed = apply_filter(chunks, filters, args.clearance)

    print("=" * 70)
    print(f" 질의: {args.q}")
    print("=" * 70)
    print(f" 색인 {len(chunks):,}청크 · 보안등급 {args.clearance} · "
          f"검색 대상 {len(allowed):,}건" + (f" · 필터 {filters}" if filters else ""))

    if args.mode == "compare":
        kw = engine.keyword(args.q, args.top, allowed)
        vc = engine.vector(args.q, args.top, allowed)
        hy, _, _ = engine.hybrid(args.q, args.top, allowed, args.vector_weight)
        sem, _, _ = engine.semantic(args.q, args.top, allowed, args.vector_weight)

        show(chunks, kw, "① 키워드만 (BM25) — 정확한 용어·숫자에 강하다")
        show(chunks, vc, "② 벡터만 (의미) — 표현이 달라도 찾는다")
        show(chunks, hy, "③ 하이브리드 (RRF k=60) — 두 결과를 순위로 융합")
        show(chunks, sem, "④ 하이브리드 + 재순위 — 폐지 문서를 밀어낸다")

        # 겹침 분석 — «왜 합쳐야 하는가»를 수치로
        kw_set = {i for i, _ in kw}
        vc_set = {i for i, _ in vc}
        hy_set = {i for i, _, _ in hy}
        print()
        print(" ── 겹침 분석")
        print(f"    키워드 상위{args.top} ∩ 벡터 상위{args.top} = {len(kw_set & vc_set)}건")
        print(f"    키워드에만 있음 = {len(kw_set - vc_set)}건  "
              f"(벡터가 놓친 것)")
        print(f"    벡터에만 있음   = {len(vc_set - kw_set)}건  "
              f"(키워드가 놓친 것)")
        print(f"    하이브리드가 두 쪽에서 건진 것 = "
              f"{len(hy_set & (kw_set | vc_set))}건")
        if len(kw_set & vc_set) == args.top:
            print("    → 두 방식이 완전히 일치합니다. 이 질의는 하이브리드의 이득이 작습니다.")
        elif len(kw_set & vc_set) <= args.top // 3:
            print("    → 두 방식이 크게 다릅니다. 하이브리드의 이득이 큰 질의입니다.")

    elif args.mode == "semantic":
        sem, kw, vc = engine.semantic(args.q, args.top, allowed, args.vector_weight)
        show(chunks, sem, "하이브리드 + 재순위")
        print()
        print(" ── 재순위 근거")
        for rank, (i, s, why) in enumerate(sem[:3], start=1):
            print(f"    {rank}. {chunks[i]['title'][:40]}")
            print(f"       점수 {s:.4f} ← {why}")
    else:
        hy, kw, vc = engine.hybrid(args.q, args.top, allowed, args.vector_weight)
        show(chunks, hy, "하이브리드 (RRF)")
        print()
        print(" ── RRF 기여도 (어느 검색에서 몇 위였는가)")
        for rank, (i, s, contrib) in enumerate(hy[:3], start=1):
            parts = ", ".join(
                f"{'키워드' if k == 0 else '벡터'} {v}위" for k, v in sorted(contrib.items()))
            print(f"    {rank}. {chunks[i]['title'][:40]}")
            print(f"       RRF {s:.5f} = {parts}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
