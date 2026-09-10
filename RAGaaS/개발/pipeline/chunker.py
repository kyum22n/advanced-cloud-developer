# -*- coding: utf-8 -*-
"""청킹 — 문서를 검색 단위로 자른다.

핵심 원칙: «청크 = 하나의 답이 담기는 최소 단위»
    너무 크면 관련 없는 내용이 섞여 벡터가 흐려지고, LLM 컨텍스트도 낭비된다.
    너무 작으면 답에 필요한 맥락이 잘려 나가 근거가 불완전해진다.

이 구현이 다른 청커와 다른 점 — «문서 유형별로 다르게 자른다»
    고정 크기로 전부 자르는 것이 가장 흔한 실수다. 이 코퍼스에는
      · FAQ(평균 200자)      — 이미 하나의 질문-답 쌍이다. 자르면 답이 깨진다.
      · 규정 조문(평균 250자) — «조»가 이미 법적 의미 단위다. 자르면 안 된다.
      · 매뉴얼(최대 8천자)    — 반드시 잘라야 한다. 단, «절» 경계를 지켜야 한다.
    가 섞여 있다. 유형을 무시하고 800자로 자르면 앞의 둘은 손상되고 뒤만 이득을 본다.

Azure AI Search 와의 대응
    이 로컬 청커는 Azure 의 SplitSkill(통합 벡터화)과 «같은 결과»를 내려는 것이 아니다.
    목적은 두 가지다.
      ① 배포 전에 청킹 결과를 눈으로 확인하고 파라미터를 정한다 (비용 0)
      ② 정한 파라미터를 skillset JSON 으로 내보내 Azure 가 같은 방식으로 자르게 한다
    Azure SplitSkill 의 maximumPageLength 도 «문자» 단위이므로 기준이 일치한다.

사용:
    python chunker.py --in ../data/corpus.jsonl --out ../data/chunks.jsonl
"""
import argparse
import io
import json
import os
import re
import sys

# stdout 을 «한 번만» UTF-8 로 감싼다.
# 이미 UTF-8 이면 건드리지 않는다 — 이중 래핑하면 안쪽 래퍼가 수거될 때
# 하위 버퍼가 닫혀 «I/O operation on closed file» 이 난다.
if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# ═══════════════════════════════════════════════════════════ 파라미터
#
# 이 숫자들에는 근거가 있어야 한다. «해 보니 되더라»는 설계가 아니다.

TARGET_CHARS = 800
#   근거: 한국어 800자 ≈ 500~600 토큰.
#   text-embedding-3-large 의 입력 한계는 8,191 토큰이지만 한계까지 채우면 안 된다.
#   청크가 커질수록 «한 벡터에 여러 주제»가 섞여 코사인 유사도가 평평해진다.
#   답변 1건에 청크 5개를 넣어도 3,000 토큰 수준이라 LLM 컨텍스트에도 여유가 있다.

MAX_CHARS = 1200
#   경계를 지키려다 목표를 넘길 때의 상한. 이보다 크면 강제로 자른다.

OVERLAP_CHARS = 120
#   근거: 문단 경계에서 잘린 문장이 양쪽 청크에 모두 남도록 하는 최소치.
#   한국어 한 문장이 평균 40~60자이므로 2~3문장이 겹친다.
#   중첩을 키우면 재현율은 오르지만 인덱스 크기와 임베딩 비용이 비례해 늘어난다.

MIN_CHARS = 120
#   이보다 짧은 조각은 앞 청크에 흡수한다. 파편은 검색 노이즈가 된다.

# 자르지 «않을» 문서 유형 — 이미 하나의 의미 단위다
ATOMIC_DOC_TYPES = {"FAQ", "문의이력", "공지", "서식안내", "규정"}

# 절 제목 패턴 — 이 경계를 우선해서 자른다
SECTION_PATTERNS = [
    re.compile(r"^\s*\d+\.\s+\S.*$"),          # "1. 제도 개요"
    re.compile(r"^\s*■\s*\S.*$"),               # "■ 목적"
    re.compile(r"^\s*제\d+장\s+\S.*$"),         # "제2장 휴가"
    re.compile(r"^\s*제\d+조\([^)]+\)\s*$"),    # "제12조(연차유급휴가)"
    re.compile(r"^\s*부칙\s*$"),
]


def is_section_head(line):
    return any(p.match(line) for p in SECTION_PATTERNS)


def split_into_sections(text):
    """절 경계로 나눈다. 경계가 없으면 문단(빈 줄)으로 나눈다."""
    lines = text.split("\n")
    heads = [i for i, l in enumerate(lines) if is_section_head(l)]

    if len(heads) >= 2:
        bounds = heads + [len(lines)]
        # 첫 절 앞의 머리말(제목·발행정보)은 첫 절에 붙인다
        sections = []
        if bounds[0] > 0:
            sections.append("\n".join(lines[: bounds[0]]).strip())
        for a, b in zip(bounds[:-1], bounds[1:]):
            chunk = "\n".join(lines[a:b]).strip()
            if chunk:
                sections.append(chunk)
        return [s for s in sections if s]

    # 절 경계가 없으면 빈 줄 기준
    parts = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    return parts or [text.strip()]


def split_by_size(text, target, maximum, overlap):
    """크기 기준 분할. 문장 경계를 최대한 지킨다.

    한국어 문장 종결(다./요./음표)과 줄바꿈을 경계 후보로 본다.
    경계를 찾지 못하면 어쩔 수 없이 문자 단위로 자른다.
    """
    if len(text) <= maximum:
        return [text]

    # 문장 끝 위치를 미리 모아 둔다
    ends = [m.end() for m in re.finditer(r"(?:[.!?]|다\.|요\.|음\.|함\.)\s|\n", text)]

    chunks = []
    start = 0
    while start < len(text):
        if len(text) - start <= maximum:
            chunks.append(text[start:].strip())
            break

        ideal = start + target
        hard = start + maximum

        # 목표 지점 이후 첫 문장 경계를 찾되, 상한을 넘지 않게 한다
        cut = next((e for e in ends if ideal <= e <= hard), None)
        if cut is None:
            # 목표 앞쪽에서라도 경계를 찾는다
            candidates = [e for e in ends if start + MIN_CHARS < e < ideal]
            cut = candidates[-1] if candidates else hard

        piece = text[start:cut].strip()
        if piece:
            chunks.append(piece)

        # 다음 청크는 중첩만큼 앞에서 시작한다
        start = max(cut - overlap, start + MIN_CHARS)

    return [c for c in chunks if c]


def chunk_document(doc, target=TARGET_CHARS, maximum=MAX_CHARS, overlap=OVERLAP_CHARS):
    """문서 하나를 청크 목록으로 만든다.

    각 청크에는 «문서 제목»을 머리말로 붙인다.
    청크만 떼어 놓고 보면 무슨 문서의 어느 부분인지 알 수 없기 때문이다.
    이 머리말은 임베딩 품질에도, LLM 이 근거를 인용할 때도 도움이 된다.
    """
    content = doc["content"]
    doc_type = doc["doc_type"]
    title = doc["title"]

    # ⚠️ 실제로 임베딩되는 것은 «머리말 + 본문»이다.
    #    본문만 기준으로 자르면 머리말을 붙인 뒤 상한을 넘는다.
    #    예산에서 머리말 길이를 먼저 빼야 «상한을 지킨다»는 말이 참이 된다.
    prefix_len = len(f"[{title}]\n")
    budget_target = max(target - prefix_len, MIN_CHARS)
    budget_max = max(maximum - prefix_len, MIN_CHARS * 2)

    # ── ① 짧고 이미 완결된 유형은 자르지 않는다
    if doc_type in ATOMIC_DOC_TYPES or len(content) <= budget_max:
        pieces = [content]
        strategy = "atomic"
    else:
        # ── ② 절 경계로 먼저 나눈다
        sections = split_into_sections(content)
        pieces = []
        for sec in sections:
            if len(sec) <= budget_max:
                pieces.append(sec)
            else:
                # ── ③ 절이 너무 길면 크기 기준으로 재분할
                pieces.extend(split_by_size(sec, budget_target, budget_max, overlap))
        strategy = "section+size"

        # ── ④ 너무 짧은 파편은 앞 청크에 흡수한다
        #     ⚠️ 흡수 결과가 상한을 넘으면 안 된다.
        #        «파편 제거»가 «상한 위반»을 만들면 얻는 것보다 잃는 것이 크다.
        merged = []
        for p in pieces:
            if (merged and len(p) < MIN_CHARS
                    and len(merged[-1]) + len(p) + 1 <= budget_max):
                merged[-1] = merged[-1] + "\n" + p
            else:
                merged.append(p)
        pieces = merged

    chunks = []
    for i, piece in enumerate(pieces):
        # 머리말이 이미 본문에 있으면 중복해서 붙이지 않는다
        body = piece if piece.lstrip().startswith(title[:12]) else f"[{title}]\n{piece}"
        chunks.append({
            "chunk_id": f"{doc['doc_id']}-c{i:03d}",
            "parent_id": doc["doc_id"],
            "chunk_index": i,
            "chunk_total": len(pieces),
            "chunk_strategy": strategy,
            "title": title,
            "content": body,
            "char_count": len(body),
            # ── 필터·팩싯에 쓰는 메타데이터는 청크마다 복사한다.
            #    검색은 청크 단위로 이루어지므로 청크가 스스로를 설명할 수 있어야 한다.
            "category": doc["category"],
            "subcategory": doc["subcategory"],
            "topic": doc["topic"],
            "doc_type": doc_type,
            "doc_group": doc.get("doc_group"),
            "version": doc.get("version"),
            "status": doc.get("status"),
            "effective_date": doc.get("effective_date"),
            "expiry_date": doc.get("expiry_date"),
            "owner_dept": doc.get("owner_dept"),
            "audience": doc.get("audience", []),
            "security_level": doc.get("security_level"),
            "keywords": doc.get("keywords", []),
            "source_uri": doc.get("source_uri"),
            "updated_at": doc.get("updated_at"),
            "trap": doc.get("trap"),
        })
    return chunks


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="문서 유형별 청킹")
    ap.add_argument("--in", dest="src", default=os.path.join(here, "..", "data", "corpus.jsonl"))
    ap.add_argument("--out", dest="dst", default=os.path.join(here, "..", "data", "chunks.jsonl"))
    ap.add_argument("--target", type=int, default=TARGET_CHARS)
    ap.add_argument("--max", dest="maximum", type=int, default=MAX_CHARS)
    ap.add_argument("--overlap", type=int, default=OVERLAP_CHARS)
    args = ap.parse_args()

    src = os.path.abspath(args.src)
    dst = os.path.abspath(args.dst)

    print("=" * 68)
    print(" 청킹 — 문서 유형별 전략")
    print("=" * 68)
    print(f" 목표 {args.target}자 · 최대 {args.maximum}자 · 중첩 {args.overlap}자")
    print(f" 자르지 않는 유형: {', '.join(sorted(ATOMIC_DOC_TYPES))}")
    print()

    docs, chunks = 0, []
    by_type = {}
    with io.open(src, encoding="utf-8") as f:
        for line in f:
            doc = json.loads(line)
            docs += 1
            cs = chunk_document(doc, args.target, args.maximum, args.overlap)
            chunks.extend(cs)
            t = doc["doc_type"]
            agg = by_type.setdefault(t, {"docs": 0, "chunks": 0, "chars": 0, "maxc": 0})
            agg["docs"] += 1
            agg["chunks"] += len(cs)
            agg["chars"] += sum(c["char_count"] for c in cs)
            agg["maxc"] = max(agg["maxc"], max(c["char_count"] for c in cs))

    with io.open(dst, "w", encoding="utf-8", newline="\n") as f:
        for c in chunks:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")

    sizes = sorted(c["char_count"] for c in chunks)
    over = [c for c in chunks if c["char_count"] > args.maximum]
    # ⚠️ 짧은 FAQ 는 «완결된 답»이지 파편이 아니다.
    #    원자 유형까지 과소로 세면 지표가 거짓말을 한다.
    tiny = [c for c in chunks
            if c["char_count"] < MIN_CHARS and c["chunk_strategy"] != "atomic"]
    atomic_short = sum(1 for c in chunks
                       if c["char_count"] < MIN_CHARS and c["chunk_strategy"] == "atomic")

    print(f" {'문서유형':<10} {'문서':>7} {'청크':>7} {'배율':>6} {'평균자':>7} {'최대자':>7}")
    print(" " + "-" * 52)
    for t, a in sorted(by_type.items(), key=lambda kv: -kv[1]["chunks"]):
        print(f" {t:<10} {a['docs']:>7,} {a['chunks']:>7,} "
              f"{a['chunks']/a['docs']:>6.2f} {a['chars']//a['chunks']:>7,} {a['maxc']:>7,}")

    stats = {
        "문서수": docs,
        "청크수": len(chunks),
        "청크배율": round(len(chunks) / docs, 3),
        "파라미터": {"목표자수": args.target, "최대자수": args.maximum,
                    "중첩자수": args.overlap, "최소자수": MIN_CHARS},
        "청크자수": {
            "최소": sizes[0], "최대": sizes[-1],
            "중앙값": sizes[len(sizes) // 2],
            "평균": round(sum(sizes) / len(sizes), 1),
            "p90": sizes[int(len(sizes) * 0.9)],
            "p99": sizes[int(len(sizes) * 0.99)],
        },
        "총자수": sum(sizes),
        "상한초과": len(over),
        "과소청크_분할된것": len(tiny),
        "짧은원자청크": {
            "건수": atomic_short,
            "설명": "짧지만 완결된 FAQ 등. 결함이 아니라 정상이다",
        },
        "원자비율": round(
            sum(1 for c in chunks if c["chunk_strategy"] == "atomic") / len(chunks) * 100, 1),
        "유형별": {t: {"문서": a["docs"], "청크": a["chunks"],
                     "배율": round(a["chunks"] / a["docs"], 2),
                     "평균자수": a["chars"] // a["chunks"], "최대자수": a["maxc"]}
                 for t, a in by_type.items()},
        # 임베딩 비용 추정의 근거가 되는 값. 토큰 환산은 별도 단계에서 한다.
        "임베딩대상_총자수": sum(sizes),
    }
    stats_path = os.path.join(os.path.dirname(dst), "chunk_stats.json")
    with io.open(stats_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)

    print()
    print("-" * 68)
    print(f" 문서 {docs:,} → 청크 {len(chunks):,} (배율 {len(chunks)/docs:.2f})")
    print(f" 청크 자수  중앙값 {stats['청크자수']['중앙값']:,} · "
          f"p90 {stats['청크자수']['p90']:,} · 최대 {sizes[-1]:,}")
    print(f" 상한 초과 {len(over)}건 · 분할 파편 {len(tiny)}건")
    print(f" 짧은 원자 청크 {atomic_short:,}건 (완결된 FAQ 등 — 정상)")
    print()
    print(f"  → {dst}")
    print(f"  → {stats_path}")

    if over:
        print()
        print(f" ⚠️ 상한({args.maximum}자)을 넘는 청크가 {len(over)}건 있습니다.")
        print("    문장 경계를 찾지 못해 강제 분할된 경우이거나 원자 유형입니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
