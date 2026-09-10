# -*- coding: utf-8 -*-
"""검색 품질 평가 — 전략별로 «숫자»를 낸다.

측정하는 것
    Recall@K   정답 문서 중 상위 K 에 들어온 비율   — «찾았는가»
    Precision@K 상위 K 중 정답인 비율               — «쓸데없는 것이 섞였는가»
    MRR        첫 정답의 순위 역수                  — «맨 위에 있는가»
    nDCG@K     순위 가중 정확도                     — 위쪽 정답에 더 큰 점수
    보안위반    제한 문서가 노출된 횟수              — ★ 0이어야 한다
    범위밖오탐  답이 없는데 근거를 찾은 비율          — ★ 환각 위험 지표

비교하는 전략
    keyword    BM25 만
    vector     벡터만
    hybrid     BM25 + 벡터 + RRF
    semantic   하이브리드 + 재순위
    filtered   하이브리드 + status='현행' 필터 + 재순위   ← 필터가 재순위보다 확실하다
    boosted    하이브리드 + 재순위 + 문서유형 권위 가중     ← FAQ 노이즈를 누른다
    agentic    쿼리 분해 + 병렬 + 합성

⚠️ 이 평가는 «로컬 LSA 임베딩» 기준이다.
   Azure OpenAI 임베딩으로 바꾸면 vector/hybrid/semantic 의 절대 수치가 달라진다.
   그러나 «전략 간의 상대적 순서»와 «어떤 유형에서 무엇이 필요한가»는
   대체로 유지된다. 그것이 이 평가의 쓸모다.

사용:
    python eval_retrieval.py --k 5
    python eval_retrieval.py --k 5 --strategies hybrid,semantic,filtered,agentic
"""
import argparse
import io
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEV = os.path.join(HERE, "..", "..", "개발")
sys.path.insert(0, os.path.join(DEV, "search"))
sys.path.insert(0, os.path.join(DEV, "pipeline"))

if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

from hybrid import HybridSearch, apply_filter, naive_rerank  # noqa: E402
from agentic import LocalAgenticSearch  # noqa: E402


# ═══════════════════════════════════════════════════════════ 지표

def recall_at_k(retrieved, relevant, k):
    if not relevant:
        return None
    hit = len(set(retrieved[:k]) & set(relevant))
    return hit / len(relevant)


def precision_at_k(retrieved, relevant, k):
    if not relevant or not retrieved:
        return None
    hit = len(set(retrieved[:k]) & set(relevant))
    return hit / min(k, len(retrieved))


def mrr(retrieved, relevant):
    if not relevant:
        return None
    rel = set(relevant)
    for i, r in enumerate(retrieved, start=1):
        if r in rel:
            return 1.0 / i
    return 0.0


def ndcg_at_k(retrieved, relevant, k):
    """이진 관련성 기준 nDCG.

    상위에 있는 정답에 더 큰 점수를 준다.
    Recall 은 «5위에 있든 1위에 있든» 같게 보지만, 사용자 경험은 다르다.
    """
    if not relevant:
        return None
    rel = set(relevant)
    dcg = sum(1.0 / math.log2(i + 1)
              for i, r in enumerate(retrieved[:k], start=1) if r in rel)
    ideal = sum(1.0 / math.log2(i + 1)
                for i in range(1, min(len(rel), k) + 1))
    return dcg / ideal if ideal else 0.0


def mean(values):
    vals = [v for v in values if v is not None]
    return sum(vals) / len(vals) if vals else None


# ═══════════════════════════════════════════════════════════ 권위 가중
#
# 문서 유형별 신뢰도. «규정»이 «문의이력»보다 권위 있다는 것은 도메인 지식이다.
# 검색 엔진은 이것을 스스로 알 수 없으므로 사람이 알려 줘야 한다.
AUTHORITY_BOOST = {
    "규정": 2.0,        # 사규 — 최종 근거
    "규정전문": 1.8,
    "안내서": 1.7,      # 기준표·한도표가 여기 있다
    "지침": 1.5,        # 실무 절차의 공식 문서
    "매뉴얼": 1.4,
    "서식안내": 1.2,
    "공지": 1.1,        # 최신이지만 시한이 있다
    "FAQ": 1.0,         # 편의 요약 — 수치가 다를 수 있다
    "문의이력": 0.8,    # 개별 사례. 일반화하면 위험하다
}


# ═══════════════════════════════════════════════════════════ 전략 실행

def run_strategy(name, engine, agent, chunks, query, allowed, k):
    """전략을 실행해 «부모 문서 ID» 목록을 순위순으로 돌려준다.

    청크가 아니라 문서 단위로 평가하는 이유 —
    같은 문서의 청크 3개가 상위 3개를 차지해도 «정답 문서 1개»를 찾은 것이다.
    청크 단위로 세면 그것이 «정답 3개»로 부풀려져 지표가 거짓말을 한다.
    """
    pool = max(k * 6, 40)

    if name == "keyword":
        res = engine.keyword(query, pool, allowed)
        order = [i for i, _ in res]
    elif name == "vector":
        res = engine.vector(query, pool, allowed)
        order = [i for i, _ in res]
    elif name == "hybrid":
        fused, _, _ = engine.hybrid(query, pool, allowed, recall=pool)
        order = [i for i, _, _ in fused]
    elif name == "semantic":
        fused, _, _ = engine.hybrid(query, pool, allowed, recall=pool)
        order = [i for i, _, _ in naive_rerank(query, fused, chunks, top=pool,
                                              idf=engine.bm25.idf)]
    elif name == "filtered":
        # ★ 폐지 문서를 «검색 전에» 제외한다.
        #   재순위로 밀어내는 것보다 확실하다 —
        #   재순위는 «점수 경쟁»이라 다른 문서가 더 높으면 정답이 밀려나지만,
        #   필터는 «후보에서 아예 뺀다». 결정적이다.
        current = {i for i in allowed if chunks[i].get("status") == "현행"}
        fused, _, _ = engine.hybrid(query, pool, current, recall=pool)
        order = [i for i, _, _ in naive_rerank(query, fused, chunks, top=pool,
                                              idf=engine.bm25.idf)]
    elif name == "boosted":
        # ★ 문서 «유형»에 가중을 준다.
        #   이 코퍼스는 FAQ 3,600건이 규정·안내서 수백 건을 수적으로 압도한다.
        #   "연차휴가 한도가 며칠인가요?" 에 대해 FAQ 변형 수십 개가 상위를 채우고
        #   정작 권위 있는 «운영기준»은 15위로 밀린다.
        #   Azure 에서는 scoringProfile 의 magnitude/tag 부스팅으로 같은 일을 한다.
        fused, _, _ = engine.hybrid(query, pool, allowed, recall=pool)
        reranked = naive_rerank(query, fused, chunks, top=pool, idf=engine.bm25.idf)
        boosted = [(i, s2 * AUTHORITY_BOOST.get(chunks[i]["doc_type"], 1.0), w)
                   for i, s2, w in reranked]
        order = [i for i, _, _ in sorted(boosted, key=lambda x: -x[1])]
    elif name == "agentic":
        out = agent.retrieve(query, top=pool, allowed=allowed, per_subquery=pool)
        order = [i for i, _, _ in out["결과"]]
    elif name == "agentic+boost":
        # ★ 운영 후보 구성 — 쿼리 분해와 권위 가중은 «다른 문제»를 푼다.
        #   분해: 여러 주제가 섞인 질문에서 각 주제의 근거를 찾는다
        #   가중: 같은 주제 안에서 권위 있는 문서를 위로 올린다
        #   둘은 경쟁하지 않으므로 함께 쓸 수 있다.
        out = agent.retrieve(query, top=pool, allowed=allowed, per_subquery=pool)
        boosted = [(i, sc * AUTHORITY_BOOST.get(chunks[i]["doc_type"], 1.0))
                   for i, sc, _ in out["결과"]]
        order = [i for i, _ in sorted(boosted, key=lambda x: -x[1])]
    else:
        raise ValueError(name)

    # 청크 → 문서로 접기 (순서 유지, 중복 제거)
    seen, docs = set(), []
    for i in order:
        pid = chunks[i]["parent_id"]
        if pid not in seen:
            seen.add(pid)
            docs.append(pid)
    return docs, order


# ═══════════════════════════════════════════════════════════ 평가

def evaluate(cases, engine, agent, chunks, strategies, k, clearance="사내"):
    allowed = apply_filter(chunks, {}, clearance)
    results = {s: [] for s in strategies}

    for case in cases:
        query = case["질의"]
        relevant = case.get("정답문서", [])
        loose = case.get("느슨한판정", False)
        topic = case.get("정답주제")

        for s in strategies:
            docs, chunk_order = run_strategy(s, engine, agent, chunks,
                                             query, allowed, k)

            # ── 느슨한 판정: 주제가 맞으면 정답으로 본다
            if loose and topic:
                topic_docs = {chunks[i]["parent_id"] for i in chunk_order
                              if chunks[i].get("topic") == topic}
                effective_relevant = list(set(relevant) | topic_docs) if topic_docs else relevant
                # 주제 일치 여부로 다시 계산
                hit_docs = [d for d in docs[:k]
                            if d in set(relevant) or d in topic_docs]
                r = 1.0 if hit_docs else 0.0
                p = len(hit_docs) / min(k, len(docs)) if docs else 0.0
                m = next((1.0 / (i + 1) for i, d in enumerate(docs)
                          if d in set(relevant) or d in topic_docs), 0.0)
                nd = ndcg_at_k(docs, effective_relevant, k)
            else:
                r = recall_at_k(docs, relevant, k)
                p = precision_at_k(docs, relevant, k)
                m = mrr(docs, relevant)
                nd = ndcg_at_k(docs, relevant, k)

            # ── 보안 위반 — 제한 문서가 결과에 있는가
            violations = 0
            if case["유형"] == "F_권한제한":
                restricted = set(case.get("제한문서", []))
                violations = len(set(docs[:k]) & restricted)

            # ── 버전 충돌 — ★ 절대 재현율이 아니라 «상대 순서»를 봐야 한다.
            #    구버전이 현행보다 위에 오면 «틀린 숫자»를 답하게 된다. 그것이 실패다.
            #    현행 문서가 5위 밖이어도, 구버전보다 위에 있으면 이 위험은 없다.
            stale_wins = None
            if case["유형"] == "C_버전충돌":
                cur = next((i for i, d in enumerate(docs)
                            if d in set(case.get("정답문서", []))), None)
                old = next((i for i, d in enumerate(docs)
                            if d in set(case.get("오답문서", []))), None)
                if old is not None:
                    stale_wins = (cur is None) or (old < cur)
                else:
                    stale_wins = False      # 구버전이 아예 안 나옴 = 안전

            # ── 범위 밖 — 답이 없는데 «강한 근거»를 찾았는가
            #    상위 결과가 나오는 것 자체는 문제가 아니다.
            #    점수가 임계값을 넘어 «자신 있게» 답하게 되는 것이 문제다.
            out_of_scope_hit = None
            if case["유형"] == "G_범위밖":
                out_of_scope_hit = len(docs[:k]) > 0

            results[s].append({
                "id": case["id"],
                "유형": case["유형"],
                "질의": query,
                "recall": r, "precision": p, "mrr": m, "ndcg": nd,
                "보안위반": violations,
                "구버전우선": stale_wins,
                "범위밖결과있음": out_of_scope_hit,
                "상위": docs[:3],
            })

    return results


def summarize(results, cases, k):
    by_case = {c["id"]: c for c in cases}
    summary = {}

    for strategy, rows in results.items():
        # 전체
        scored = [r for r in rows
                  if by_case[r["id"]]["유형"] not in ("F_권한제한", "G_범위밖")]
        summary[strategy] = {
            f"Recall@{k}": mean(r["recall"] for r in scored),
            f"Precision@{k}": mean(r["precision"] for r in scored),
            "MRR": mean(r["mrr"] for r in scored),
            f"nDCG@{k}": mean(r["ndcg"] for r in scored),
            "보안위반": sum(r["보안위반"] for r in rows),
            "범위밖_근거찾음": sum(1 for r in rows
                             if r["범위밖결과있음"] is True),
            "구버전우선": sum(1 for r in rows if r["구버전우선"] is True),
            "유형별": {},
        }
        # 유형별
        types = sorted({r["유형"] for r in rows})
        for t in types:
            sub = [r for r in rows if r["유형"] == t]
            if t == "F_권한제한":
                summary[strategy]["유형별"][t] = {
                    "보안위반": sum(r["보안위반"] for r in sub), "건수": len(sub)}
            elif t == "C_버전충돌":
                summary[strategy]["유형별"][t] = {
                    f"Recall@{k}": mean(r["recall"] for r in sub),
                    "구버전우선": sum(1 for r in sub if r["구버전우선"] is True),
                    "건수": len(sub)}
            elif t == "G_범위밖":
                summary[strategy]["유형별"][t] = {
                    "근거찾음": sum(1 for r in sub if r["범위밖결과있음"]),
                    "건수": len(sub)}
            else:
                summary[strategy]["유형별"][t] = {
                    f"Recall@{k}": mean(r["recall"] for r in sub),
                    "MRR": mean(r["mrr"] for r in sub),
                    "건수": len(sub),
                }
    return summary


def fmt(v):
    return "  —  " if v is None else f"{v:.3f}"


def main():
    ap = argparse.ArgumentParser(description="검색 품질 평가")
    ap.add_argument("--k", type=int, default=5)
    ap.add_argument("--strategies", default="keyword,vector,hybrid,semantic,boosted,agentic,agentic+boost")
    ap.add_argument("--clearance", default="사내")
    args = ap.parse_args()

    import numpy as np

    data = os.path.join(DEV, "data")
    chunks = []
    with io.open(os.path.join(data, "chunks.jsonl"), encoding="utf-8") as f:
        for line in f:
            chunks.append(json.loads(line))

    npz = np.load(os.path.join(data, "vectors.npz"), allow_pickle=False)
    vocab = {t: int(i) for t, i in zip(npz["vocab_terms"], npz["vocab_index"])}
    engine = HybridSearch(chunks, npz["vectors"], vocab, npz["idf"], npz["components"])
    agent = LocalAgenticSearch(engine, chunks)

    gs = json.load(io.open(os.path.join(HERE, "..", "goldenset", "goldenset.json"),
                           encoding="utf-8"))
    cases = gs["사례"]
    strategies = [s.strip() for s in args.strategies.split(",")]

    print("=" * 78)
    print(f" 검색 품질 평가 — K={args.k} · 사례 {len(cases)}건 · 색인 {len(chunks):,}청크")
    print("=" * 78)
    print(" ⚠️ 임베딩: 로컬 LSA. Azure OpenAI 로 바꾸면 절대 수치는 달라진다.")
    print("    전략 간 «상대 순서»와 «유형별 강약»을 보는 것이 목적이다.")
    print()

    results = evaluate(cases, engine, agent, chunks, strategies,
                       args.k, args.clearance)
    summary = summarize(results, cases, args.k)

    # ── 전체 표
    print(f" {'전략':<10} {'Recall':>8} {'Prec':>8} {'MRR':>8} {'nDCG':>8} "
          f"{'보안위반':>8} {'범위밖':>8}")
    print(" " + "-" * 62)
    for s in strategies:
        v = summary[s]
        print(f" {s:<10} {fmt(v[f'Recall@{args.k}']):>8} "
              f"{fmt(v[f'Precision@{args.k}']):>8} {fmt(v['MRR']):>8} "
              f"{fmt(v[f'nDCG@{args.k}']):>8} "
              f"{v['보안위반']:>8} {v['범위밖_근거찾음']:>8}")

    # ── 유형별 Recall
    print()
    print(" 유형별 Recall@%d" % args.k)
    types = [t for t in sorted({c["유형"] for c in cases})
             if t not in ("F_권한제한", "G_범위밖")]
    header = " " + " " * 10 + "".join(f"{t.split('_')[1][:6]:>9}" for t in types)
    print(header)
    print(" " + "-" * (10 + 9 * len(types)))
    for s in strategies:
        row = f" {s:<10}"
        for t in types:
            v = summary[s]["유형별"].get(t, {}).get(f"Recall@{args.k}")
            row += f"{fmt(v):>9}"
        print(row)

    # ── 안전 지표
    print()
    print(" 안전 지표 (낮을수록 좋다)")
    n_perm = sum(1 for c in cases if c["유형"] == "F_권한제한")
    n_oos = sum(1 for c in cases if c["유형"] == "G_범위밖")
    n_ver = sum(1 for c in cases if c["유형"] == "C_버전충돌")
    for s in strategies:
        v = summary[s]
        mark = "✓" if v["보안위반"] == 0 else "✗"
        print(f"    {mark} {s:<10} 보안위반 {v['보안위반']}/{n_perm}건 · "
              f"구버전우선 {v['구버전우선']}/{n_ver}건 · "
              f"범위밖 근거찾음 {v['범위밖_근거찾음']}/{n_oos}건")

    print()
    print(" ⚠️ «범위밖 근거찾음»이 높은 것은 검색 실패가 아니다.")
    print("    검색은 언제나 «가장 가까운» 것을 돌려준다.")
    print("    답이 없을 때 모른다고 말하는 것은 «생성 단계»의 책임이며,")
    print("    근거 점수 임계값과 시스템 프롬프트로 처리해야 한다.")

    out = {
        "K": args.k,
        "사례수": len(cases),
        "청크수": len(chunks),
        "임베딩": "local-lsa",
        "요약": summary,
        "상세": results,
        "주의": [
            "로컬 LSA 임베딩 기준. Azure OpenAI 로 재측정 필요",
            "합성 코퍼스 기준. 실제 문서로 옮기면 다시 평가해야 함",
            "범위밖 지표는 생성 단계 대책이 있어야 의미가 있음",
        ],
    }
    path = os.path.join(HERE, f"eval_result_k{args.k}.json")
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print()
    print(f"  → {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
