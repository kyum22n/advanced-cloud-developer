# -*- coding: utf-8 -*-
"""평가 세트(골든셋) 생성 — «무엇이 정답인지»를 먼저 정한다.

평가 세트가 없으면 벌어지는 일
    "검색이 잘 되는 것 같다" 는 판단은 «몇 개 질의를 눈으로 본» 결과다.
    청킹 크기를 800 → 500 으로 바꿨을 때 좋아졌는지 나빠졌는지 말할 수 없다.
    → 튜닝이 «감»이 되고, 되돌릴 근거도 남지 않는다.

이 세트가 다른 점 — 함정에서 «역으로» 만든다
    보통은 질의를 먼저 쓰고 정답을 찾는다. 그러면 «찾기 쉬운 질의»만 모인다.
    여기서는 코퍼스 생성 때 심어 둔 함정(traps.json)에서 질의를 만든다.
    정답 문서 ID 를 «생성 시점»에 이미 알고 있으므로 라벨링이 정확하다.

포함하는 유형 (MECE)
    A. 사실 조회      단일 문서로 답이 나온다               — 기본 성능
    B. 숫자 정밀도    수치가 답의 핵심이다                   — BM25·랭커 필요
    C. 버전 충돌      구버전과 신버전이 공존한다             — 최신성 처리
    D. 다중 홉        2~3개 문서를 조합해야 한다             — 에이전트 검색
    E. 동의어·구어    표현이 문서와 다르다                   — 벡터 필요
    F. 권한 제한      권한 없는 사용자에게 노출되면 안 된다  — 보안
    G. 범위 밖        답이 «없다». 모른다고 해야 한다        — 환각 방지
"""
import io
import json
import os
import sys

if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "..", "개발", "data")


def load(name):
    return json.load(io.open(os.path.join(DATA, name), encoding="utf-8"))


def chunk_ids_for(parent_id, chunks_index):
    return chunks_index.get(parent_id, [])


def build():
    traps = load("traps.json")
    corpus = {}
    with io.open(os.path.join(DATA, "corpus.jsonl"), encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            corpus[d["doc_id"]] = d

    chunks_index = {}
    with io.open(os.path.join(DATA, "chunks.jsonl"), encoding="utf-8") as f:
        for line in f:
            c = json.loads(line)
            chunks_index.setdefault(c["parent_id"], []).append(c["chunk_id"])

    cases = []
    n = [0]

    def add(**kw):
        n[0] += 1
        kw["id"] = f"Q{n[0]:03d}"
        cases.append(kw)

    # ═══════════════════════════════════ B. 숫자 정밀도
    for item in traps["데이터"]["numeric_precision"]:
        doc = corpus[item["정답"]]
        topic = item["topic"]
        add(
            유형="B_숫자정밀도",
            질의=f"{topic} 기준이 어떻게 되나요?",
            정답문서=[item["정답"]],
            정답청크=chunk_ids_for(item["정답"], chunks_index),
            기대근거=doc["content"][:160],
            검증관점="수치가 답의 핵심. 벡터만으로는 유사 문서와 구분되지 않는다",
            필요기능=["BM25", "시맨틱랭커"],
        )

    # ═══════════════════════════════════ C. 버전 충돌
    for item in traps["데이터"]["version_conflict"]:
        add(
            유형="C_버전충돌",
            질의=f"{item['topic']} 한도가 며칠인가요?",
            정답문서=[item["정답"]],
            정답청크=chunk_ids_for(item["정답"], chunks_index),
            오답문서=[item["오답"]],
            정답값=item["정답값"],
            오답값=item["오답값"],
            검증관점=("폐지된 구버전이 상위에 오면 «틀린 숫자»를 답하게 된다. "
                    "status 필터 또는 재순위로 걸러야 한다"),
            필요기능=["필터(status)", "재순위", "최신성"],
        )

    # ═══════════════════════════════════ D. 다중 홉
    for item in traps["데이터"]["multi_hop"]:
        add(
            유형="D_다중홉",
            질의=item["질문"],
            정답문서=item["필요문서"],
            정답청크=[cid for pid in item["필요문서"]
                    for cid in chunk_ids_for(pid, chunks_index)],
            검증관점=("한 문서로는 답할 수 없다. 근거 문서 «전부»를 찾아야 완전한 답이 된다. "
                    "단일 질의는 세 주제의 평균 지점을 검색하므로 어느 것도 잘 찾지 못한다"),
            필요기능=["에이전트검색", "쿼리분해"],
            최소재현율=len(item["필요문서"]),
        )

    # ═══════════════════════════════════ F. 권한 제한
    for item in traps["데이터"]["permission_scoped"]:
        add(
            유형="F_권한제한",
            질의=f"{item['topic']} 알려주세요",
            정답문서=[],                      # ★ 일반 사용자에게는 «결과 없음»이 정답
            제한문서=[item["문서"]],
            허용대상=item["허용대상"],
            검증관점=("보안등급 «제한» 문서가 일반 사용자 결과에 나타나면 «실패»다. "
                    "LLM 프롬프트로 막는 것이 아니라 검색 단계에서 배제해야 한다"),
            필요기능=["보안필터"],
            기대="결과없음_또는_제한문서제외",
        )

    # ═══════════════════════════════════ E. 동의어 · 구어체
    #   문서에는 정식 명칭이, 질의에는 약어·구어가 들어간다
    colloquial = [
        ("연차 며칠이나 남아요?", "연차휴가", "연차 ↔ 연차유급휴가"),
        ("육휴 쓰면 월급 나와요?", "육아휴직", "육휴 ↔ 육아휴직"),
        ("법카 정산 어떻게 해요", "법인카드", "법카 ↔ 법인카드"),
        ("WFH 신청하려면", "재택근무", "WFH ↔ 재택근무"),
        ("미팅룸 어떻게 잡아요", "회의실예약", "미팅룸 ↔ 회의실"),
        ("애 낳으면 며칠 쉬어요?", "경조휴가", "구어체 ↔ 배우자 출산 휴가"),
    ]
    for q, topic, note in colloquial:
        matches = [d["doc_id"] for d in corpus.values()
                   if d.get("topic") == topic and d["status"] == "현행"][:8]
        add(
            유형="E_동의어구어",
            질의=q,
            정답주제=topic,
            정답문서=matches,
            정답청크=[cid for pid in matches for cid in chunk_ids_for(pid, chunks_index)],
            검증관점=f"{note}. BM25 는 표기가 달라 못 찾는다. 벡터 또는 동의어 맵이 필요",
            필요기능=["벡터검색", "동의어맵"],
            느슨한판정=True,      # 주제가 맞으면 정답으로 본다
        )

    # ═══════════════════════════════════ A. 사실 조회 (기본 성능)
    basic = [
        ("연차휴가 어떻게 신청하나요?", "연차휴가", "절차"),
        ("출장비 정산 필요 서류가 무엇인가요?", "출장비정산", "서류"),
        ("경조휴가 승인 권한은 누구에게 있나요?", "경조휴가", "승인자"),
        ("비품신청 처리 기간이 얼마나 걸리나요?", "비품신청", "소요기간"),
        ("건강검진 담당 부서가 어디인가요?", "건강검진", "담당"),
        ("재택근무 신청 기한이 언제까지인가요?", "재택근무", "기한"),
        ("법인카드 신청했는데 반려됐어요. 왜 그런가요?", "법인카드", "반려"),
        ("육아휴직 관련 규정이 어떻게 되나요?", "육아휴직", "근거"),
        ("회의실예약 소급 적용이 되나요?", "회의실예약", "가부"),
        ("성과급 사용하면 불이익이 있나요?", "성과급", "불이익"),
    ]
    for q, topic, intent in basic:
        matches = [d["doc_id"] for d in corpus.values()
                   if d.get("topic") == topic and d["status"] == "현행"][:10]
        add(
            유형="A_사실조회",
            질의=q,
            정답주제=topic,
            정답의도=intent,
            정답문서=matches,
            정답청크=[cid for pid in matches for cid in chunk_ids_for(pid, chunks_index)],
            검증관점="단일 문서로 답이 나오는 기본 질의. 여기서 실패하면 나머지는 볼 필요가 없다",
            필요기능=["하이브리드"],
            느슨한판정=True,
        )

    # ═══════════════════════════════════ G. 범위 밖 — ★ 가장 중요
    for q in traps["데이터"].get("out_of_scope", []) or [
        "경쟁사 연봉 테이블 알려줘",
        "다음 분기 조직개편 계획은 어떻게 되나요?",
        "옆자리 동료 연봉이 얼마인가요?",
        "우리 회사 주가 전망 알려줘",
        "내년 최저임금은 얼마로 정해지나요?",
    ]:
        add(
            유형="G_범위밖",
            질의=q if isinstance(q, str) else str(q),
            정답문서=[],
            검증관점=("★ 지식 베이스에 답이 «없다». "
                    "모른다고 답해야 하며, 그럴듯한 문서를 근거로 지어내면 «실패»다. "
                    "RAG 시스템의 가장 흔하고 위험한 실패 모드"),
            필요기능=["근거임계값", "거절응답"],
            기대="모름_응답",
        )

    return cases


def main():
    cases = build()

    by_type = {}
    for c in cases:
        by_type[c["유형"]] = by_type.get(c["유형"], 0) + 1

    out = {
        "설명": "인사·총무 RAGaaS 평가 세트. 코퍼스 생성 시 심은 함정에서 역으로 만들었다.",
        "생성기준": "traps.json + corpus.jsonl",
        "총건수": len(cases),
        "유형별": dict(sorted(by_type.items())),
        "판정규칙": {
            "느슨한판정": "정답주제가 일치하면 정답으로 본다 (문서가 여러 개인 경우)",
            "엄격한판정": "정답문서 ID 가 상위 K 에 있어야 한다",
            "F_권한제한": "제한문서가 결과에 «없어야» 통과",
            "G_범위밖": "근거 점수가 임계값 미만이어야 통과 (모름 응답 유도)",
        },
        "사례": cases,
    }

    path = os.path.join(HERE, "goldenset.json")
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)

    print("=" * 68)
    print(" 평가 세트 생성")
    print("=" * 68)
    for t, n in sorted(by_type.items()):
        print(f"  {t:<16} {n:>3}건")
    print("  " + "-" * 26)
    print(f"  {'합계':<16} {len(cases):>3}건")
    print()
    print(f"  → {path}")
    print()
    print(" ⚠️ 이 세트는 «합성 데이터»에서 만들어졌습니다.")
    print("    실제 사내 문서로 옮길 때는 실사용 질의 로그로 다시 만들어야 합니다.")
    print("    합성 질의는 사용자가 실제로 묻는 방식과 다를 수 있습니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
