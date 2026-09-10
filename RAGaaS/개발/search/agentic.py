# -*- coding: utf-8 -*-
"""에이전트 검색 — 복잡한 질문을 하위 쿼리로 쪼개 병렬 검색 후 합친다.

하이브리드 검색으로 부족한 지점
    "3년차 개발직이 육아휴직을 쓰면 급여와 평가는 어떻게 되나요?"
    이 질문의 답은 «한 문서»에 없다. 세 문서에 흩어져 있다.
      · 육아휴직 급여 처리
      · 휴직자 인사평가 처리
      · 육아휴직 신청 자격
    하이브리드 검색은 이 질문을 «하나의 벡터»로 만들어 던진다.
    세 주제의 평균 지점에 있는 벡터라서, 어느 문서와도 특별히 가깝지 않다.
    → 상위 결과가 애매해진다.

에이전트 검색이 하는 일
    ① 쿼리 계획   LLM 이 질문을 하위 질문으로 분해한다
    ② 병렬 실행   각 하위 질문을 «따로» 검색한다 (각각 시맨틱 재순위)
    ③ 결과 합성   결과를 하나로 합치고 참조·활동 로그를 남긴다

두 가지 구현
    · AzureAgenticSearch  실제 Azure 지식 베이스 호출 (운영)
    · LocalAgenticSearch  규칙 기반 분해 + 로컬 하이브리드 (오프라인 검증)

⚠️ LocalAgenticSearch 의 «쿼리 계획»은 LLM 이 아니라 규칙이다.
   Azure 는 LLM 이 분해하므로 훨씬 유연하다.
   로컬 구현의 목적은 «분해하면 왜 좋아지는지»를 비용 없이 보여 주는 것이다.

사용:
    python agentic.py --q "3년차 개발직이 육아휴직 쓰면 급여와 평가는 어떻게 되나요"
    python agentic.py --q "..." --compare      # 하이브리드 단일 쿼리와 비교
"""
import argparse
import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "pipeline"))

if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

from hybrid import (  # noqa: E402
    HybridSearch, apply_filter, parse_filter, reciprocal_rank_fusion,
)


# ═══════════════════════════════════════════════════════════ 쿼리 분해 (로컬)
#
# 규칙 기반이다. LLM 분해의 «저렴한 근사»이며, 한계가 분명하다.
# 그럼에도 유용한 이유 — 분해의 «효과»는 분해 품질이 완벽하지 않아도 드러난다.

# 접속 표현 — 이 앞뒤로 질문이 갈라진다
_CONJUNCTIONS = [
    "와 ", "과 ", "및 ", "그리고 ", "또한 ", ", ",
]

# 여러 주제를 동시에 묻는 신호어
_MULTI_ASPECT = [
    ("급여", "급여"), ("평가", "인사평가"), ("수당", "수당"), ("대체휴무", "대체휴무"),
    ("퇴직금", "퇴직금"), ("연차", "연차휴가"), ("퇴직연금", "퇴직연금"),
    ("절차", "신청 절차"), ("서류", "필요 서류"), ("기한", "신청 기한"),
    ("한도", "한도"), ("자격", "신청 자격"), ("승인", "승인 권한"),
]

# 조건 표현 — 필터로 바꿀 수 있는 것
_CONDITION_PATTERNS = [
    (re.compile(r"(\d+)\s*년차"), "근속"),
    (re.compile(r"(개발직|기획직|영업직|디자인직|관리직|연구직|생산직)"), "직군"),
    (re.compile(r"(정규직|계약직|파견직|인턴|촉탁직)"), "고용형태"),
    (re.compile(r"(신입|수습|관리자|팀장|임원)"), "대상"),
]


def plan_queries(question, max_subqueries=4):
    """질문을 하위 쿼리로 분해한다.

    Returns:
        {"subqueries": [...], "conditions": {...}, "method": "..."}

    ⚠️ Azure 는 LLM 이 이 일을 한다. 여기서는 규칙으로 흉내 낸다.
       규칙의 한계: 표현이 예상 밖이면 분해하지 못한다.
       그래도 «분해 여부»가 결과를 얼마나 바꾸는지는 확인할 수 있다.
    """
    # ── ① 조건 추출 (필터 후보)
    conditions = {}
    for pattern, label in _CONDITION_PATTERNS:
        m = pattern.search(question)
        if m:
            conditions[label] = m.group(1)

    # ── ② 핵심 주제어 추출 — 조건을 걷어낸 나머지
    core = question
    for pattern, _ in _CONDITION_PATTERNS:
        core = pattern.sub("", core)
    core = re.sub(r"[?!.]", " ", core).strip()

    # ── ③ 여러 측면을 묻는지 확인
    aspects = [full for key, full in _MULTI_ASPECT if key in question]

    subqueries = []
    if len(aspects) >= 2:
        # 주제 × 측면으로 쪼갠다.
        # "육아휴직 쓰면 급여와 평가는" → "육아휴직 급여" + "육아휴직 인사평가"
        subject = _extract_subject(core, aspects)
        for a in aspects[:max_subqueries]:
            subqueries.append(f"{subject} {a}".strip())
        method = "측면 분해"
    else:
        # 접속 표현으로 갈라 본다
        parts = _split_on_conjunctions(core)
        if len(parts) >= 2:
            subqueries = [p.strip() for p in parts if len(p.strip()) >= 4][:max_subqueries]
            method = "접속 분해"
        else:
            subqueries = [core]
            method = "분해 없음 (단일 질의)"

    # 조건을 각 하위 쿼리에 되돌려 붙인다 — 검색어로서 도움이 되는 것만
    if conditions.get("직군"):
        subqueries = [f"{q}" for q in subqueries]   # 직군은 필터로만 쓴다

    return {
        "subqueries": subqueries or [core],
        "conditions": conditions,
        "method": method,
    }


def _extract_subject(core, aspects):
    """측면 어휘를 걷어내고 남는 주제어를 찾는다."""
    s = core
    for _, full in _MULTI_ASPECT:
        s = s.replace(full, " ")
    # 조사·서술어 꼬리를 정리한다
    s = re.sub(r"(는|은|이|가|을|를|의|에|으로|로|와|과|및|그리고)\s", " ", s)
    s = re.sub(r"(어떻게|어떠한|얼마나|무엇|어디|언제|누가|되나요|되는지|하나요|"
               r"인가요|가능한가요|있나요|쓰면|사용하면|신청하면)", " ", s)
    words = [w for w in s.split() if len(w) >= 2]
    return " ".join(words[:3])


def _split_on_conjunctions(text):
    parts = [text]
    for c in _CONJUNCTIONS:
        out = []
        for p in parts:
            out.extend(p.split(c))
        parts = out
    return parts


# ═══════════════════════════════════════════════════════════ 로컬 에이전트 검색

class LocalAgenticSearch:
    """규칙 분해 + 로컬 하이브리드 + RRF 합성."""

    def __init__(self, engine, chunks):
        self.engine = engine
        self.chunks = chunks

    def retrieve(self, question, top=8, allowed=None, per_subquery=20):
        plan = plan_queries(question)
        activity = []
        result_sets = []

        for i, sq in enumerate(plan["subqueries"], start=1):
            fused, kw, vc = self.engine.hybrid(
                sq, top=per_subquery, allowed=allowed, recall=per_subquery * 2)
            # 각 하위 쿼리 결과에도 재순위를 적용한다 (Azure 도 하위 쿼리마다 시맨틱 재순위)
            from hybrid import naive_rerank
            reranked = naive_rerank(sq, fused, self.chunks, top=per_subquery,
                                    idf=self.engine.bm25.idf)
            result_sets.append([(i2, s) for i2, s, _ in reranked])
            activity.append({
                "하위쿼리": sq,
                "키워드결과": len(kw),
                "벡터결과": len(vc),
                "재순위후": len(reranked),
                "상위": [self.chunks[i2]["title"][:38] for i2, _, _ in reranked[:3]],
            })

        # ── 결과 합성 — 하위 쿼리 결과를 RRF 로 합친다
        merged = reciprocal_rank_fusion(result_sets)

        return {
            "질문": question,
            "계획": plan,
            "활동로그": activity,
            "결과": merged[:top],
        }


# ═══════════════════════════════════════════════════════════ Azure 에이전트 검색

class AzureAgenticSearch:
    """실제 Azure 지식 베이스 호출.

    자격 증명은 환경 변수와 관리 ID 로만 받는다. API 키를 쓰지 않는다.
      AZURE_SEARCH_ENDPOINT
      AZURE_SEARCH_KNOWLEDGE_BASE

    ⚠️ 이 클래스는 실제로 과금된다.
       Azure AI Search 의 검색 토큰 + Azure OpenAI 의 계획·합성 토큰.
    """

    def __init__(self, endpoint=None, knowledge_base=None, api_version="2026-04-01"):
        self.endpoint = endpoint or os.environ.get("AZURE_SEARCH_ENDPOINT")
        self.knowledge_base = knowledge_base or os.environ.get(
            "AZURE_SEARCH_KNOWLEDGE_BASE", "hr-ga-knowledge-base")
        self.api_version = api_version
        if not self.endpoint:
            raise RuntimeError("AZURE_SEARCH_ENDPOINT 환경 변수가 필요합니다.")

    def _token(self):
        from azure.identity import DefaultAzureCredential
        cred = DefaultAzureCredential()
        return cred.get_token("https://search.azure.com/.default").token

    def retrieve(self, messages, security_filter=None, reasoning_effort=None):
        """지식 베이스에 검색 작업을 요청한다.

        Args:
            messages: [{"role": "user", "content": [{"type":"text","text":"..."}]}]
                      대화 이력을 함께 넣으면 «지난번에 말한 그거» 같은 질문도 처리된다.
            security_filter: OData 필터. ★ 보안 강제는 여기서 한다.
            reasoning_effort: minimal | low | medium (미리 보기)

        Returns:
            {"response": [...], "references": [...], "activity": [...]}
        """
        import urllib.request

        url = (f"{self.endpoint}/knowledgeBases/{self.knowledge_base}"
               f"/retrieve?api-version={self.api_version}")

        body = {"messages": messages}
        if security_filter:
            # ★ 검색 단계에서 배제한다. LLM 에게 «보여 주지 마»라고 말하는 것은 방어가 아니다.
            body["knowledgeSourceParams"] = [{
                "knowledgeSourceName": os.environ.get(
                    "AZURE_SEARCH_KNOWLEDGE_SOURCE", "hr-ga-knowledge-source"),
                "kind": "searchIndex",
                "filterAddOn": security_filter,
            }]
        if reasoning_effort:
            body["retrievalReasoningEffort"] = reasoning_effort

        req = urllib.request.Request(
            url,
            data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self._token()}",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))


# ═══════════════════════════════════════════════════════════ 출력

def show_agentic(result, chunks, limit=6):
    plan = result["계획"]
    print()
    print(" ── ① 쿼리 계획")
    print(f"    방법: {plan['method']}")
    if plan["conditions"]:
        print(f"    추출 조건: {plan['conditions']}   ← 필터 후보")
    for i, sq in enumerate(plan["subqueries"], start=1):
        print(f"    하위쿼리 {i}: {sq}")

    print()
    print(" ── ② 병렬 실행")
    for a in result["활동로그"]:
        print(f"    «{a['하위쿼리']}»")
        print(f"      키워드 {a['키워드결과']}건 · 벡터 {a['벡터결과']}건 "
              f"→ 재순위 {a['재순위후']}건")
        for t in a["상위"]:
            print(f"        · {t}")

    print()
    print(" ── ③ 결과 합성 (하위 쿼리 결과를 RRF 로 병합)")
    for rank, (i, score, contrib) in enumerate(result["결과"][:limit], start=1):
        c = chunks[i]
        flag = "  ⚠️폐지" if c.get("status") == "폐지" else ""
        origin = ", ".join(f"쿼리{k+1} {v}위" for k, v in sorted(contrib.items()))
        print(f"    {rank}. [{score:.5f}] {c['title'][:48]}{flag}")
        print(f"       {c['doc_type']} · {c['category']}>{c['subcategory']} ← {origin}")


def main():
    data = os.path.join(HERE, "..", "data")

    ap = argparse.ArgumentParser(description="에이전트 검색 (쿼리 분해 + 병렬 + 합성)")
    ap.add_argument("--q", required=True)
    ap.add_argument("--top", type=int, default=6)
    ap.add_argument("--filter", default="")
    ap.add_argument("--clearance", choices=["공개", "사내", "제한"], default="사내")
    ap.add_argument("--compare", action="store_true",
                    help="단일 하이브리드 질의와 나란히 비교한다")
    ap.add_argument("--azure", action="store_true",
                    help="⚠️ 실제 Azure 지식 베이스를 호출한다 (과금)")
    args = ap.parse_args()

    if args.azure:
        print("=" * 70)
        print(" Azure 에이전트 검색 — ⚠️ 실제 과금됩니다")
        print("=" * 70)
        client = AzureAgenticSearch()
        out = client.retrieve(
            messages=[{"role": "user",
                       "content": [{"type": "text", "text": args.q}]}],
            security_filter=f"security_level ne '제한'" if args.clearance != "제한" else None,
        )
        print(json.dumps(out, ensure_ascii=False, indent=2)[:4000])
        return 0

    import numpy as np

    chunks = []
    with io.open(os.path.join(data, "chunks.jsonl"), encoding="utf-8") as f:
        for line in f:
            chunks.append(json.loads(line))

    npz = np.load(os.path.join(data, "vectors.npz"), allow_pickle=False)
    vocab = {t: int(i) for t, i in zip(npz["vocab_terms"], npz["vocab_index"])}
    engine = HybridSearch(chunks, npz["vectors"], vocab, npz["idf"], npz["components"])

    allowed = apply_filter(chunks, parse_filter(args.filter), args.clearance)

    print("=" * 70)
    print(f" 질문: {args.q}")
    print("=" * 70)
    print(f" 색인 {len(chunks):,}청크 · 검색 대상 {len(allowed):,}건 "
          f"· 보안등급 {args.clearance}")

    agent = LocalAgenticSearch(engine, chunks)
    result = agent.retrieve(args.q, top=args.top, allowed=allowed)
    show_agentic(result, chunks, args.top)

    if args.compare:
        print()
        print("=" * 70)
        print(" 비교: 단일 하이브리드 질의 (분해 없음)")
        print("=" * 70)
        from hybrid import naive_rerank
        fused, _, _ = engine.hybrid(args.q, top=50, allowed=allowed, recall=50)
        single = naive_rerank(args.q, fused, chunks, top=args.top,
                              idf=engine.bm25.idf)
        for rank, (i, s, _why) in enumerate(single, start=1):
            c = chunks[i]
            print(f"    {rank}. [{s:.4f}] {c['title'][:48]}")
            print(f"       {c['doc_type']} · {c['category']}>{c['subcategory']}")

        # 두 방식이 찾은 «서로 다른» 문서를 센다
        agentic_ids = {chunks[i]["parent_id"] for i, _, _ in result["결과"][:args.top]}
        single_ids = {chunks[i]["parent_id"] for i, _, _ in single}
        print()
        print(" ── 차이")
        print(f"    에이전트만 찾은 문서: {len(agentic_ids - single_ids)}건")
        print(f"    단일 질의만 찾은 문서: {len(single_ids - agentic_ids)}건")
        print(f"    공통: {len(agentic_ids & single_ids)}건")
        if len(result["계획"]["subqueries"]) == 1:
            print("    → 이 질문은 분해되지 않았습니다. 에이전트 검색의 이득이 없습니다.")
        elif agentic_ids - single_ids:
            print("    → 분해 덕분에 단일 질의가 놓친 근거를 찾았습니다.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
