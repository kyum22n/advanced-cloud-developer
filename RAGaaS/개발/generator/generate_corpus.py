# -*- coding: utf-8 -*-
"""인사·총무 가상 지식 코퍼스 생성기 — 1만 건 이상.

⚠️ 생성되는 모든 내용은 «허구»다. 실재하는 회사·인물·규정·금액이 아니다.
   실제 사규를 RAG 실험에 쓰면 개인정보·기밀 문제가 생기므로,
   «구조»만 현실과 같고 «내용»은 지어낸 데이터를 쓴다.

설계 의도 — 그냥 많이 만드는 것이 목적이 아니다
   ① 문서 «유형»이 달라야 한다 (규정/FAQ/문의이력/공지…) — 청킹 전략이 유형별로 달라지기 때문
   ② 길이 분포가 현실을 닮아야 한다 — 짧은 FAQ 와 긴 규정이 섞여야 청킹 검증이 된다
   ③ 검색을 «틀리게» 만드는 함정이 들어 있어야 한다 — 버전 충돌·중복·숫자·다중 홉
   ④ 메타데이터가 필터로 쓸 만해야 한다 — 분류·상태·보안등급·시행일

사용:
    python generate_corpus.py --out ../data --seed 20260829
"""
import argparse
import io
import json
import os
import random
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# stdout 을 «한 번만» UTF-8 로 감싼다.
# 이미 UTF-8 이면 건드리지 않는다 — 이중 래핑하면 안쪽 래퍼가 수거될 때
# 하위 버퍼가 닫혀 «I/O operation on closed file» 이 난다.
if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

from korean import resolve_josa, check_unresolved  # noqa: E402
from taxonomy import (  # noqa: E402
    COMPANY, COMPANY_FULL, INTRANET, DEPARTMENTS, JOB_FAMILIES, GRADES,
    EMPLOYMENT_TYPES, WORKSITES, TAXONOMY, FLAT_TOPICS, STATUSES,
    SECURITY_LEVELS, AUDIENCES, SYNONYMS, TRAPS, QUESTION_PATTERNS, INTENT_ANSWERS,
    APPROVERS, SYSTEMS, FORMS, CHANNELS,
)

TODAY = date(2026, 8, 29)
NL2 = chr(10) * 2   # 빈 줄. 이스케이프 문제를 피하려고 상수로 둔다


# ═══════════════════════════════════════════════════════════ 유틸

def d(offset_days):
    return (TODAY + timedelta(days=offset_days)).isoformat()


def pick(rnd, seq, k=1):
    return rnd.choice(seq) if k == 1 else rnd.sample(seq, min(k, len(seq)))


def owner_for(category):
    return "인사팀" if category == "인사" else "총무팀"


def money(rnd, low, high, step=10000):
    return f"{rnd.randrange(low, high + 1, step):,}원"


class Corpus:
    """문서를 모으고 ID 를 부여한다."""

    def __init__(self):
        self.docs = []
        self._counters = {}

    def add(self, doc_type_code, **fields):
        n = self._counters.get(doc_type_code, 0) + 1
        self._counters[doc_type_code] = n
        fields["doc_id"] = f"{doc_type_code}-{n:05d}"
        fields.setdefault("company", COMPANY)

        # ★ 조사를 확정한다.
        #   «육아휴직은(는)» 같은 표기가 남으면 토크나이저가 이상하게 쪼개
        #   임베딩과 BM25 매칭이 모두 나빠진다. 합성 데이터라도 언어적으로 정상이어야
        #   실험 결과를 믿을 수 있다.
        for key in ("title", "content"):
            if key in fields and isinstance(fields[key], str):
                fields[key] = resolve_josa(fields[key])

        self.docs.append(fields)
        return fields


# ═══════════════════════════════════════════════════════════ 1. 규정 (조문)

RULE_BOOKS = [
    ("인사규정",       "인사", ["채용", "인사이동", "평가", "승진", "휴가", "휴직", "퇴직"]),
    ("취업규칙",       "인사", ["근태", "휴가", "노무", "급여"]),
    ("복무규정",       "인사", ["근태", "노무"]),
    ("급여규정",       "인사", ["급여", "보험"]),
    ("퇴직급여규정",   "인사", ["퇴직", "보험"]),
    ("교육훈련규정",   "인사", ["교육"]),
    ("인사평가규정",   "인사", ["평가", "승진"]),
    ("징계규정",       "인사", ["노무"]),
    ("유연근무규정",   "인사", ["근태"]),
    ("모성보호규정",   "인사", ["휴직", "휴가"]),
    ("총무규정",       "총무", ["비품", "자산", "사무공간", "문서"]),
    ("자산관리규정",   "총무", ["자산", "비품"]),
    ("구매규정",       "총무", ["구매", "계약"]),
    ("계약관리규정",   "총무", ["계약"]),
    ("출장여비규정",   "총무", ["출장", "경비"]),
    ("경비처리규정",   "총무", ["경비"]),
    ("법인차량운영규정", "총무", ["차량"]),
    ("보안관리규정",   "총무", ["출입보안", "문서"]),
    ("복리후생규정",   "총무", ["복리후생"]),
    ("문서관리규정",   "총무", ["문서"]),
]

ARTICLE_BODIES = [
    "① {subject}은(는) {actor}의 승인을 받아 시행한다.\n"
    "② 제1항에 따른 승인은 {system}을(를) 통하여 신청하며, 신청일로부터 {days}일 이내에 처리한다.\n"
    "③ 부득이한 사유로 기한 내 처리가 어려운 경우 {approver}이(가) {ext}일의 범위에서 연장할 수 있다.",

    "① {subject}의 기준은 다음 각 호와 같다.\n"
    "  1. {grade1}: {n1}{unit}\n"
    "  2. {grade2}: {n2}{unit}\n"
    "  3. {grade3}: {n3}{unit}\n"
    "② 제1항의 기준은 {emp_type}에게도 동일하게 적용한다. 다만 {exception}의 경우 별도로 정한다.",

    "① 직원은 {subject}을(를) 신청하기 전에 {prereq}을(를) 완료하여야 한다.\n"
    "② {subject}은(는) 연간 {limit}회를 초과할 수 없다.\n"
    "③ 제2항에도 불구하고 {actor}이(가) 업무상 필요하다고 인정하는 경우 초과할 수 있다.",

    "① {subject}에 소요되는 비용은 회사가 부담한다. 다만 다음 각 호의 경우는 그러하지 아니하다.\n"
    "  1. 직원의 귀책사유로 인한 경우\n"
    "  2. {exception}에 해당하는 경우\n"
    "② 회사가 부담하는 금액의 한도는 {amount}으로 하며, 초과분은 직원이 부담한다.",

    "① {subject}에 관한 사항은 {owner}이(가) 관장한다.\n"
    "② {owner}은(는) {subject}의 운영 현황을 매 {period}마다 {approver}에게 보고하여야 한다.\n"
    "③ 이 조에서 정하지 아니한 사항은 {related}을(를) 준용한다.",

    "① 다음 각 호의 어느 하나에 해당하는 직원은 {subject}을(를) 신청할 수 없다.\n"
    "  1. 수습기간 중인 직원\n"
    "  2. {exception} 중인 직원\n"
    "  3. 직전 {period} 이내에 {subject} 관련 규정을 위반한 사실이 있는 직원\n"
    "② 제1항 제3호의 경우 {approver}의 승인이 있으면 예외로 한다.",
]


def gen_rules(corpus, rnd):
    """규정 조문. 하나의 규정이 여러 조로 나뉘고, 각 조가 하나의 레코드가 된다."""
    for book, category, subs in RULE_BOOKS:
        n_articles = rnd.randint(14, 34)
        version_major = rnd.randint(1, 4)
        effective = d(-rnd.randint(200, 1500))

        for art in range(1, n_articles + 1):
            sub = pick(rnd, subs)
            leaf = pick(rnd, TAXONOMY[category][sub])
            body = pick(rnd, ARTICLE_BODIES).format(
                subject=leaf,
                actor=pick(rnd, APPROVERS),
                approver=pick(rnd, APPROVERS),
                system=pick(rnd, SYSTEMS),
                days=rnd.choice([3, 5, 7, 10, 14]),
                ext=rnd.choice([3, 5, 7]),
                grade1=GRADES[0], n1=rnd.randint(1, 15),
                grade2=GRADES[2], n2=rnd.randint(16, 30),
                grade3=GRADES[4], n3=rnd.randint(31, 45),
                unit=rnd.choice(["일", "만원", "시간", "회"]),
                emp_type=pick(rnd, EMPLOYMENT_TYPES),
                exception=rnd.choice(["휴직", "징계", "파견", "수습", "겸직"]),
                prereq=rnd.choice(["직속 상급자와의 사전 협의", "관련 교육 이수",
                                   "전자결재 상신", "부서 인력계획 반영"]),
                limit=rnd.randint(2, 12),
                amount=money(rnd, 100000, 3000000, 50000),
                owner=owner_for(category),
                period=rnd.choice(["분기", "반기", "연도"]),
                related=rnd.choice([b[0] for b in RULE_BOOKS]),
            )

            corpus.add(
                "RUL",
                title=f"{book} 제{art}조({leaf})",
                content=(
                    f"[{COMPANY_FULL} {book}]\n"
                    f"제{art}조({leaf})\n\n{body}\n\n"
                    f"<부칙> 이 조는 {effective}부터 시행한다."
                ),
                category=category,
                subcategory=sub,
                topic=leaf,
                doc_type="규정",
                doc_group=book,
                article_no=art,
                version=f"{version_major}.{rnd.randint(0, 9)}",
                status="현행",
                effective_date=effective,
                expiry_date=None,
                owner_dept=owner_for(category),
                audience=["전직원"],
                security_level="사내",
                keywords=[book, leaf, sub],
                source_uri=f"{INTRANET}/rules/{book}#art{art}",
                updated_at=effective,
            )


# ═══════════════════════════════════════════════════════════ 2. 지침 · 절차

PROCEDURE_STEPS = [
    "{system}에 접속하여 [{menu}] 메뉴를 선택합니다.",
    "{form}을(를) 작성하고 필수 항목을 모두 입력합니다.",
    "증빙서류({evidence})를 첨부합니다. 파일 형식은 PDF 또는 JPG 이며 개별 20MB 이하입니다.",
    "{approver}에게 결재를 상신합니다.",
    "결재 완료 후 {owner}에서 검토하며, 통상 {days} 영업일이 소요됩니다.",
    "처리 결과는 {channel}에서 확인할 수 있습니다.",
    "반려된 경우 반려 사유를 확인하고 보완하여 재상신합니다.",
]

EVIDENCE = ["가족관계증명서", "진단서", "영수증", "청첩장", "재학증명서",
            "출입국사실증명서", "견적서", "계약서 사본", "자격증 사본", "교육수료증"]


def gen_procedures(corpus, rnd, n=140):
    for _ in range(n):
        category, sub, leaf = pick(rnd, FLAT_TOPICS)
        n_steps = rnd.randint(4, 7)
        steps = pick(rnd, PROCEDURE_STEPS, n_steps)
        body = "\n".join(
            f"{i+1}. " + s.format(
                system=pick(rnd, SYSTEMS),
                menu=f"{sub} > {leaf}",
                form=pick(rnd, FORMS),
                evidence=", ".join(pick(rnd, EVIDENCE, 2)),
                approver=pick(rnd, APPROVERS),
                owner=owner_for(category),
                days=rnd.randint(1, 7),
                channel=pick(rnd, CHANNELS),
            )
            for i, s in enumerate(steps)
        )
        effective = d(-rnd.randint(30, 900))

        corpus.add(
            "GDL",
            title=f"[{sub}] {leaf} 업무 처리 지침",
            content=(
                f"■ 목적\n{leaf} 업무를 일관되게 처리하기 위한 절차를 정한다.\n\n"
                f"■ 적용 범위\n{COMPANY} 전 임직원 (단, {pick(rnd, EMPLOYMENT_TYPES)}은 별도 기준 적용)\n\n"
                f"■ 처리 절차\n{body}\n\n"
                f"■ 유의사항\n"
                f"- 신청 기한: 사유 발생일로부터 {rnd.choice([3, 5, 7, 14, 30])}일 이내\n"
                f"- 문의처: {owner_for(category)} ({pick(rnd, CHANNELS)})\n"
                f"- 근거 규정: {pick(rnd, [b[0] for b in RULE_BOOKS])}"
            ),
            category=category,
            subcategory=sub,
            topic=leaf,
            doc_type="지침",
            doc_group=f"{sub} 지침",
            version=f"{rnd.randint(1,3)}.{rnd.randint(0,9)}",
            status=rnd.choices(STATUSES, weights=[0.88, 0.08, 0.04])[0],
            effective_date=effective,
            expiry_date=None,
            owner_dept=owner_for(category),
            audience=pick(rnd, AUDIENCES, rnd.randint(1, 2)),
            security_level=rnd.choices(SECURITY_LEVELS, weights=[0.25, 0.7, 0.05])[0],
            keywords=[leaf, sub, "절차", "지침"],
            source_uri=f"{INTRANET}/guides/{sub}/{leaf}",
            updated_at=effective,
        )


# ═══════════════════════════════════════════════════════════ 3. FAQ

# 질문에 «누가/언제»를 덧붙여 변형을 만든다.
# 단순히 개수를 늘리려는 것이 아니라, 실제 FAQ 가 대상·상황별로 갈라지기 때문이다.
FAQ_QUALIFIERS = [
    "", "", "",                       # 수식어 없는 일반 질문이 가장 흔하다
    "신입사원인데 ", "계약직인데 ", "관리자인데 ", "재택근무 중인데 ",
    "수습 기간인데 ", "휴직 중인데 ", "퇴사 예정인데 ", "해외근무 중인데 ",
    "입사 6개월차인데 ", "타 부서로 전보 예정인데 ",
]


def gen_faq(corpus, rnd, n=3600):
    """FAQ 생성 — ★ 질문의 «의도»에 맞는 답변만 붙인다.

    무작위 조합을 쓰지 않는 이유:
      Q. 연차휴가 사용하면 불이익이 있나요?
      A. 연차휴가의 기준은 8시간입니다…
    처럼 질문과 답이 어긋나면 «검색이 옳은 문서를 찾았는가»를 판정할 수 없다.
    정답이 실제로 답이어야 평가가 성립한다.
    """
    seen = set()
    made = 0
    attempts = 0
    while made < n and attempts < n * 8:
        attempts += 1
        category, sub, leaf = pick(rnd, FLAT_TOPICS)
        qualifier = pick(rnd, FAQ_QUALIFIERS)
        intent, pattern = pick(rnd, QUESTION_PATTERNS)
        q = qualifier + pattern.format(topic=leaf)

        # 같은 (질문, 주제) 조합이 반복되지 않게 한다
        key = (q, leaf)
        if key in seen:
            continue
        seen.add(key)

        # ★ 의도가 같은 답변 형태에서만 고른다
        n1, n2, n3 = sorted(rnd.sample(range(1, 41), 3))
        a = pick(rnd, INTENT_ANSWERS[intent]).format(
            topic=leaf,
            system=pick(rnd, SYSTEMS),
            menu=f"{sub} > {leaf}",
            form=pick(rnd, FORMS),
            approver=pick(rnd, APPROVERS),
            approver2=pick(rnd, APPROVERS[-3:]),
            days=rnd.choice([1, 2, 3, 5, 7, 10, 14]),
            ext=rnd.choice([1, 2, 3, 5]),
            rule=pick(rnd, [b[0] for b in RULE_BOOKS]),
            art=rnd.randint(1, 40),
            condition=rnd.choice(["사전 승인을 받은 경우", "업무 관련성이 인정되는 경우",
                                  "재직 1년 이상인 경우", "부서장이 필요성을 확인한 경우"]),
            evidence=", ".join(pick(rnd, EVIDENCE, 2)),
            amount=money(rnd, 50000, 2000000, 10000),
            n=n1, n2=n2, n3=n3,
            unit=rnd.choice(["일", "만원", "시간", "회"]),
            grade=pick(rnd, GRADES),
            emp_type=pick(rnd, EMPLOYMENT_TYPES),
            period=rnd.choice(["1개월", "3개월", "6개월", "1년"]),
            owner=owner_for(category),
            channel=pick(rnd, CHANNELS),
            reason=rnd.choice(["증빙서류 누락", "신청 기한 초과", "결재선 오지정",
                               "잔여 한도 부족", "중복 신청"]),
            change_date=d(-rnd.randint(30, 700)),
            old=f"{rnd.randint(1,15)}{rnd.choice(['일','만원'])}",
            new=f"{rnd.randint(16,30)}{rnd.choice(['일','만원'])}",
        )

        # 동의어를 답변에 섞어 «BM25 로는 못 찾고 벡터로는 찾히는» 경우를 만든다
        syn_note = ""
        for canon, syns in SYNONYMS.items():
            if canon in leaf or leaf in canon:
                syn_note = (NL2 + "※ 사내에서는 «"
                            + ", ".join(syns[:3]) + "» 로도 부릅니다.")
                break

        published = d(-rnd.randint(10, 1200))
        corpus.add(
            "FAQ",
            title=q,
            content="Q. " + q + NL2 + "A. " + a + syn_note,
            category=category,
            subcategory=sub,
            topic=leaf,
            doc_type="FAQ",
            doc_group=f"{category} FAQ",
            intent=intent,
            version="1.0",
            status=rnd.choices(STATUSES, weights=[0.93, 0.04, 0.03])[0],
            effective_date=published,
            expiry_date=None,
            owner_dept=owner_for(category),
            audience=["전직원"],
            security_level=rnd.choices(SECURITY_LEVELS, weights=[0.4, 0.58, 0.02])[0],
            keywords=[leaf, sub, "FAQ", intent],
            source_uri=f"{INTRANET}/faq/{sub}#{made}",
            updated_at=published,
        )
        made += 1
    return made


# ═══════════════════════════════════════════════════════════ 4. 문의 이력

TICKET_OPENERS = [
    "안녕하세요, {topic} 관련해서 문의드립니다.",
    "{topic} 때문에 헷갈리는 게 있어서요.",
    "급하게 확인이 필요해서 문의합니다. {topic} 관련입니다.",
    "{topic} 신청하려는데 잘 안 돼서요.",
    "지난번에 안내받은 {topic} 내용이 바뀐 것 같은데 확인 부탁드립니다.",
    "{topic} 관련해서 제 상황이 좀 특수한데 가능할지 궁금합니다.",
]

TICKET_DETAILS = [
    "제가 {grade} {job}이고 {worksite}에서 근무 중인데, {situation} 상황입니다. 이 경우에도 적용되나요?",
    "{system}에서 신청하려니 «{error}» 라는 메시지가 뜹니다. 어떻게 해야 하나요?",
    "{approver}께 결재 올렸는데 {days}일째 진행이 없습니다. 다른 경로가 있나요?",
    "작년에는 {old}였는데 올해도 같은가요? 바뀌었다면 언제부터 적용인가요?",
    "{emp_type}인데도 동일하게 적용되는지 확인 부탁드립니다.",
]

TICKET_ANSWERS = [
    "문의 주셔서 감사합니다. 말씀하신 경우 {verdict}. "
    "근거는 {rule} 제{art}조이며, {system}의 [{menu}]에서 처리하실 수 있습니다. "
    "추가로 {evidence}을(를) 준비해 주세요.",

    "확인해 보니 {reason}으로 처리가 지연된 것으로 보입니다. "
    "{owner}에서 직접 처리해 드렸으며, {days} 영업일 내 반영될 예정입니다. "
    "다음부터는 {tip}",

    "말씀하신 내용은 {change_date}부터 변경되었습니다. "
    "변경 전에는 {old}였으나 현재는 {new}입니다. "
    "자세한 사항은 공지 게시판의 [{notice}]를 참고해 주세요.",

    "죄송하지만 해당 사항은 {verdict_no}. "
    "다만 {alternative}을(를) 활용하실 수 있으니 검토해 보시기 바랍니다. "
    "추가 문의는 {channel}(으)로 부탁드립니다.",
]

ERRORS = ["결재선이 지정되지 않았습니다", "잔여 일수가 부족합니다", "필수 첨부파일이 없습니다",
          "신청 기간이 아닙니다", "권한이 없습니다", "중복 신청 건이 존재합니다"]

SITUATIONS = ["입사 8개월차", "육아휴직 복직 직후", "해외파견 중", "타 부서로 전보 예정",
              "수습 종료 직전", "계약 갱신 시점", "장기 프로젝트 투입 중"]


def gen_tickets(corpus, rnd, n=4000):
    for i in range(n):
        category, sub, leaf = pick(rnd, FLAT_TOPICS)
        opener = pick(rnd, TICKET_OPENERS).format(topic=leaf)
        detail = pick(rnd, TICKET_DETAILS).format(
            grade=pick(rnd, GRADES), job=pick(rnd, JOB_FAMILIES),
            worksite=pick(rnd, WORKSITES), situation=pick(rnd, SITUATIONS),
            system=pick(rnd, SYSTEMS), error=pick(rnd, ERRORS),
            approver=pick(rnd, APPROVERS), days=rnd.randint(2, 15),
            old=f"{rnd.randint(1,20)}{rnd.choice(['일','만원','시간'])}",
            emp_type=pick(rnd, EMPLOYMENT_TYPES),
        )
        answer = pick(rnd, TICKET_ANSWERS).format(
            verdict=rnd.choice(["적용 가능합니다", "적용됩니다", "예외 승인이 필요합니다",
                                "조건부로 가능합니다"]),
            verdict_no=rnd.choice(["지원 대상이 아닙니다", "규정상 인정되지 않습니다",
                                   "현재 제도로는 처리가 어렵습니다"]),
            rule=pick(rnd, [b[0] for b in RULE_BOOKS]), art=rnd.randint(1, 40),
            system=pick(rnd, SYSTEMS), menu=f"{sub} > {leaf}",
            evidence=", ".join(pick(rnd, EVIDENCE, 2)),
            reason=rnd.choice(["결재자 부재", "첨부서류 누락", "시스템 일시 오류",
                               "부서 코드 불일치"]),
            owner=owner_for(category),
            days=rnd.randint(1, 5),
            tip=rnd.choice(["대결재자를 지정해 두시면 지연을 줄일 수 있습니다.",
                            "첨부서류 목록을 먼저 확인해 주세요.",
                            "신청 전 잔여 한도를 조회해 보시기 바랍니다."]),
            change_date=d(-rnd.randint(30, 700)),
            old=f"{rnd.randint(1,15)}{rnd.choice(['일','만원'])}",
            new=f"{rnd.randint(16,30)}{rnd.choice(['일','만원'])}",
            notice=f"{leaf} 제도 개선 안내",
            alternative=pick(rnd, [l for _, _, l in FLAT_TOPICS]),
            channel=pick(rnd, CHANNELS),
        )

        asked = d(-rnd.randint(1, 1000))
        # 사번은 가상 패턴. 실명·연락처는 쓰지 않는다.
        emp = f"EMP-{rnd.randrange(10000, 99999)}"

        corpus.add(
            "TKT",
            title=f"[문의] {leaf} - {opener[:24]}",
            content=(
                f"■ 문의 (작성자: {emp} / {pick(rnd, DEPARTMENTS)})\n"
                f"{opener}\n{detail}\n\n"
                f"■ 답변 ({owner_for(category)})\n{answer}\n\n"
                f"■ 처리 결과: {rnd.choice(['완료', '완료', '완료', '부분 처리', '반려'])}"
            ),
            category=category,
            subcategory=sub,
            topic=leaf,
            doc_type="문의이력",
            doc_group=f"{category} 문의이력",
            version="1.0",
            status="현행",
            effective_date=asked,
            expiry_date=None,
            owner_dept=owner_for(category),
            audience=["전직원"],
            security_level=rnd.choices(SECURITY_LEVELS, weights=[0.1, 0.85, 0.05])[0],
            keywords=[leaf, sub, "문의"],
            source_uri=f"{INTRANET}/tickets/{i+1:06d}",
            updated_at=asked,
        )


# ═══════════════════════════════════════════════════════════ 5. 공지

NOTICE_SHAPES = [
    "{topic} 제도가 {date}부터 다음과 같이 변경됩니다.\n"
    "- 변경 전: {old}\n- 변경 후: {new}\n"
    "- 적용 대상: {audience}\n- 문의: {owner}\n\n"
    "변경 사유는 {reason}이며, 기존 신청 건은 {transition}",

    "{date}에 {system} 정기 점검이 예정되어 있습니다.\n"
    "- 점검 시간: {date} 22:00 ~ 익일 02:00\n"
    "- 영향: 해당 시간 중 {topic} 신청 불가\n"
    "- 대응: 점검 전 신청을 완료해 주시기 바랍니다.",

    "{topic} 신청 기간을 안내드립니다.\n"
    "- 신청 기간: {date} ~ {date2}\n- 대상: {audience}\n"
    "- 신청 방법: {system} [{menu}]\n- 필수 서류: {evidence}\n"
    "기간 내 미신청 시 다음 회차까지 대기하셔야 합니다.",

    "{topic} 관련 유의사항을 다시 한번 안내드립니다.\n"
    "최근 {issue} 사례가 늘고 있습니다.\n"
    "- 반드시 {action}해 주시기 바랍니다.\n"
    "- 위반 시 {consequence}될 수 있습니다.\n문의: {owner}",
]


def gen_notices(corpus, rnd, n=1200):
    for i in range(n):
        category, sub, leaf = pick(rnd, FLAT_TOPICS)
        published_offset = -rnd.randint(1, 900)
        published = d(published_offset)
        # 공지는 «시한»이 있다 — 지난 공지가 상위에 오면 안 되는 것을 검증하기 위함
        expiry = d(published_offset + rnd.randint(14, 400))

        body = pick(rnd, NOTICE_SHAPES).format(
            topic=leaf,
            date=d(published_offset + rnd.randint(1, 30)),
            date2=d(published_offset + rnd.randint(31, 60)),
            old=f"{rnd.randint(1,15)}{rnd.choice(['일','만원','시간'])}",
            new=f"{rnd.randint(16,30)}{rnd.choice(['일','만원','시간'])}",
            audience=pick(rnd, AUDIENCES),
            owner=owner_for(category),
            reason=rnd.choice(["관련 법령 개정", "임직원 의견 반영", "내부 감사 지적사항 개선",
                               "제도 운영 효율화"]),
            transition=rnd.choice(["종전 기준을 적용합니다.", "변경 기준으로 재신청이 필요합니다.",
                                   "자동으로 전환됩니다."]),
            system=pick(rnd, SYSTEMS),
            menu=f"{sub} > {leaf}",
            evidence=", ".join(pick(rnd, EVIDENCE, 2)),
            issue=rnd.choice(["증빙 누락", "기한 초과 신청", "중복 신청", "규정 오적용"]),
            action=rnd.choice(["사전 결재를 완료", "증빙을 원본으로 제출",
                               "기한 내 신청", "담당자와 사전 협의"]),
            consequence=rnd.choice(["처리가 지연", "반려", "환수 조치", "감사 지적"]),
        )

        expired = date.fromisoformat(expiry) < TODAY
        corpus.add(
            "NTC",
            title=f"[공지] {leaf} 관련 안내 ({published[:7]})",
            content=f"■ 공지사항\n{body}\n\n게시일: {published} / 유효기한: {expiry}",
            category=category,
            subcategory=sub,
            topic=leaf,
            doc_type="공지",
            doc_group=f"{category} 공지",
            version="1.0",
            status="폐지" if expired else "현행",
            effective_date=published,
            expiry_date=expiry,
            owner_dept=owner_for(category),
            audience=[pick(rnd, AUDIENCES)],
            security_level=rnd.choices(SECURITY_LEVELS, weights=[0.55, 0.44, 0.01])[0],
            keywords=[leaf, sub, "공지"],
            source_uri=f"{INTRANET}/notices/{i+1:06d}",
            updated_at=published,
        )


# ═══════════════════════════════════════════════════════════ 6. 서식 안내

def gen_forms(corpus, rnd, n=400):
    for i in range(n):
        category, sub, leaf = pick(rnd, FLAT_TOPICS)
        form = pick(rnd, FORMS)
        published = d(-rnd.randint(30, 1000))
        corpus.add(
            "FRM",
            title=f"[서식] {form} 작성 안내 ({leaf})",
            content=(
                f"■ 서식명: {form}\n"
                f"■ 용도: {leaf} 신청 시 사용\n"
                f"■ 작성 요령\n"
                f"  - 신청 구분: {leaf} 선택\n"
                f"  - 기간: 시작일과 종료일을 모두 입력 (반차는 오전/오후 구분)\n"
                f"  - 사유: {rnd.randint(20, 100)}자 이내로 구체적으로 기재\n"
                f"  - 첨부: {', '.join(pick(rnd, EVIDENCE, 2))}\n"
                f"■ 결재선: 신청자 → 팀장 → {pick(rnd, APPROVERS)}\n"
                f"■ 제출처: {owner_for(category)}\n"
                f"■ 다운로드: {INTRANET}/forms/{form}.hwp\n"
                f"■ 근거: {pick(rnd, [b[0] for b in RULE_BOOKS])}"
            ),
            category=category,
            subcategory=sub,
            topic=leaf,
            doc_type="서식안내",
            doc_group="서식 안내",
            version=f"1.{rnd.randint(0,5)}",
            status="현행",
            effective_date=published,
            expiry_date=None,
            owner_dept=owner_for(category),
            audience=["전직원"],
            security_level="공개",
            keywords=[form, leaf, "서식"],
            source_uri=f"{INTRANET}/forms/{i+1:04d}",
            updated_at=published,
        )


# ═══════════════════════════════════════════════════════════ 7. 안내서 (표 포함)

def gen_handbooks(corpus, rnd, n=900):
    for i in range(n):
        category, sub, leaf = pick(rnd, FLAT_TOPICS)
        published = d(-rnd.randint(30, 1100))

        # 표를 포함시킨다 — 청킹이 표를 쪼개면 답이 망가지는 것을 검증하기 위함
        rows = "\n".join(
            f"| {g} | {rnd.randint(5, 30)}일 | {money(rnd, 100000, 2000000, 50000)} | "
            f"{rnd.choice(['가능', '불가', '조건부'])} |"
            for g in GRADES
        )
        corpus.add(
            "HBK",
            title=f"[안내] {leaf} 제도 안내서",
            content=(
                f"■ {leaf} 제도 개요\n"
                f"{COMPANY}는 임직원의 {rnd.choice(['업무 몰입', '일·생활 균형', '역량 개발', '건강 증진'])}을 "
                f"지원하기 위해 {leaf} 제도를 운영합니다.\n\n"
                f"■ 지원 기준\n"
                f"| 직급 | 한도 | 지원금액 | 이월 |\n"
                f"| --- | --- | --- | --- |\n{rows}\n\n"
                f"■ 신청 방법\n"
                f"{pick(rnd, SYSTEMS)} > {sub} > {leaf} 메뉴에서 신청합니다.\n\n"
                f"■ 자주 묻는 질문\n"
                f"- Q. 중도 입사자도 되나요? A. 입사일 기준 비례 적용합니다.\n"
                f"- Q. 이월이 되나요? A. {rnd.choice(['최대 1회 이월 가능합니다.', '이월되지 않습니다.'])}\n"
                f"- Q. 퇴직 시에는? A. 미사용분은 {rnd.choice(['정산합니다.', '소멸합니다.'])}\n\n"
                f"■ 담당: {owner_for(category)}"
            ),
            category=category,
            subcategory=sub,
            topic=leaf,
            doc_type="안내서",
            doc_group=f"{sub} 안내서",
            version=f"{rnd.randint(1,3)}.0",
            status=rnd.choices(STATUSES, weights=[0.9, 0.07, 0.03])[0],
            effective_date=published,
            expiry_date=None,
            owner_dept=owner_for(category),
            audience=pick(rnd, AUDIENCES, rnd.randint(1, 2)),
            security_level=rnd.choices(SECURITY_LEVELS, weights=[0.3, 0.65, 0.05])[0],
            keywords=[leaf, sub, "안내"],
            source_uri=f"{INTRANET}/handbook/{i+1:04d}",
            updated_at=published,
        )


# ═══════════════════════════════════════════════════════════ 8. 장문 문서
#
# ★ 왜 «긴» 문서가 반드시 있어야 하는가
#   짧은 문서만 1만 건 있으면 청킹 단계가 사실상 «아무 일도 하지 않는» 통과 지점이 된다.
#   그러면 청킹 전략(크기·중첩·경계)을 비교할 근거가 없고,
#   「임베딩 모델의 입력 토큰 한계」라는 실제 제약도 드러나지 않는다.
#
#   현실의 사내 지식은 «짧은 FAQ 수천 건 + 긴 규정 수십 건»의 이중 분포를 갖는다.
#   그 분포를 재현해야 «문서 유형별로 청킹을 달리해야 한다»는 결론이 데이터로 뒷받침된다.

def gen_full_rulebooks(corpus, rnd):
    """규정 전문(全文) — 조문을 모두 이어 붙인 긴 문서.

    앞의 gen_rules 가 만든 «조 단위» 문서와 «같은 내용»을 담는 것이 의도다.
    실제 사내 포털에도 전문 PDF 와 조문 검색이 함께 존재하며,
    이것이 근사 중복(near-duplicate)을 만들어 검색 다양성 문제를 드러낸다.
    """
    for book, category, subs in RULE_BOOKS:
        n_articles = rnd.randint(28, 55)
        parts = [
            f"{COMPANY_FULL}\n{book}\n\n"
            f"제1장 총칙\n\n"
            f"제1조(목적) 이 규정은 {COMPANY}(이하 «회사»라 한다)의 "
            f"{', '.join(subs)}에 관한 사항을 정함을 목적으로 한다.\n\n"
            f"제2조(적용범위) 이 규정은 회사에 근무하는 모든 임직원에게 적용한다. "
            f"다만 별도의 계약이나 규정이 있는 경우에는 그에 따른다.\n\n"
            f"제3조(용어의 정의) 이 규정에서 사용하는 용어의 뜻은 다음과 같다.\n"
            f"  1. «직원»이란 회사와 근로계약을 체결한 자를 말한다.\n"
            f"  2. «관리자»란 팀장 이상의 직책을 부여받은 직원을 말한다.\n"
            f"  3. «소정근로시간»이란 법정근로시간의 범위에서 회사와 직원이 정한 시간을 말한다.\n"
        ]
        chapter = 2
        for art in range(4, n_articles + 4):
            if art % 8 == 0:
                chapter += 1
                parts.append(f"\n제{chapter}장 {pick(rnd, subs)}\n")
            sub = pick(rnd, subs)
            leaf = pick(rnd, TAXONOMY[category][sub])
            body = pick(rnd, ARTICLE_BODIES).format(
                subject=leaf, actor=pick(rnd, APPROVERS), approver=pick(rnd, APPROVERS),
                system=pick(rnd, SYSTEMS), days=rnd.choice([3, 5, 7, 10, 14]),
                ext=rnd.choice([3, 5, 7]),
                grade1=GRADES[0], n1=rnd.randint(1, 15),
                grade2=GRADES[2], n2=rnd.randint(16, 30),
                grade3=GRADES[4], n3=rnd.randint(31, 45),
                unit=rnd.choice(["일", "만원", "시간", "회"]),
                emp_type=pick(rnd, EMPLOYMENT_TYPES),
                exception=rnd.choice(["휴직", "징계", "파견", "수습", "겸직"]),
                prereq=rnd.choice(["직속 상급자와의 사전 협의", "관련 교육 이수",
                                   "전자결재 상신", "부서 인력계획 반영"]),
                limit=rnd.randint(2, 12),
                amount=money(rnd, 100000, 3000000, 50000),
                owner=owner_for(category), period=rnd.choice(["분기", "반기", "연도"]),
                related=rnd.choice([b[0] for b in RULE_BOOKS]),
            )
            parts.append(f"\n제{art}조({leaf})\n{body}\n")

        effective = d(-rnd.randint(200, 1500))
        parts.append(
            f"\n\n부칙\n"
            f"제1조(시행일) 이 규정은 {effective}부터 시행한다.\n"
            f"제2조(경과조치) 이 규정 시행 전에 신청된 사항은 종전의 규정에 따른다.\n"
            f"제3조(다른 규정과의 관계) 이 규정에서 정하지 아니한 사항은 "
            f"{rnd.choice([b[0] for b in RULE_BOOKS])} 및 관계 법령을 따른다.\n"
        )

        corpus.add(
            "DOC",
            title=f"{book} (전문)",
            content="".join(parts),
            category=category,
            subcategory=subs[0],
            topic=book,
            doc_type="규정전문",
            doc_group=book,
            version=f"{rnd.randint(1, 5)}.0",
            status="현행",
            effective_date=effective,
            expiry_date=None,
            owner_dept=owner_for(category),
            audience=["전직원"],
            security_level="사내",
            keywords=[book, "전문", "사규"] + subs,
            source_uri=f"{INTRANET}/rules/{book}/full.pdf",
            updated_at=effective,
        )


LONGFORM_SECTIONS = [
    ("제도 개요", "{COMPANY}는 임직원의 {purpose}을(를) 지원하기 위해 {topic} 제도를 운영합니다. "
                  "이 제도는 {year}년 도입되어 현재까지 {count}회 개정되었으며, "
                  "직전 개정은 {last}에 이루어졌습니다. 제도의 목적은 다음과 같습니다.\n"
                  "  · {goal1}\n  · {goal2}\n  · {goal3}\n"
                  "제도 운영은 {owner}이(가) 총괄하며, 각 부서의 {role} 담당자가 실무를 지원합니다."),
    ("적용 대상", "이 제도는 다음 기준을 충족하는 직원에게 적용됩니다.\n"
                  "  · 고용형태: {emp1}, {emp2}\n  · 재직기간: {tenure} 이상\n"
                  "  · 근무지: 전 사업장 (재택근무자 포함)\n"
                  "다만 다음의 경우에는 적용이 제한되거나 별도 기준이 적용됩니다.\n"
                  "  · 수습기간 중인 직원: {probation}\n"
                  "  · 휴직 중인 직원: {onleave}\n"
                  "  · 징계 처분 중인 직원: 처분 종료 후 {after}부터 적용\n"
                  "적용 여부가 불분명한 경우 {owner}에 사전 문의하시기 바랍니다."),
    ("지원 기준", "직급 및 근속연수에 따른 지원 기준은 다음과 같습니다.\n\n"
                  "| 직급 | 근속 1년 미만 | 근속 1~3년 | 근속 3~5년 | 근속 5년 이상 |\n"
                  "| --- | --- | --- | --- | --- |\n"
                  "| 사원 | {a1} | {a2} | {a3} | {a4} |\n"
                  "| 선임 | {b1} | {b2} | {b3} | {b4} |\n"
                  "| 책임 | {c1} | {c2} | {c3} | {c4} |\n"
                  "| 수석 | {d1} | {d2} | {d3} | {d4} |\n\n"
                  "위 표의 금액은 세전 기준이며, 실제 지급액은 관련 세법에 따라 원천징수 후 지급됩니다. "
                  "중도 입사자는 입사일 기준으로 월할 계산하여 적용합니다."),
    ("신청 절차", "신청은 다음 순서로 진행됩니다.\n"
                  "1단계. {system} 접속 후 [{menu}] 메뉴 선택\n"
                  "2단계. {form} 작성 — 신청 구분, 기간, 사유를 빠짐없이 기재\n"
                  "3단계. 증빙서류 첨부 ({evidence})\n"
                  "4단계. 결재 상신 — 결재선은 «신청자 → 팀장 → {approver}»\n"
                  "5단계. {owner} 검토 — 통상 {days} 영업일 소요\n"
                  "6단계. 결과 확인 — {channel}에서 확인 가능\n\n"
                  "반려된 경우 반려 사유를 확인하여 보완 후 재상신할 수 있습니다. "
                  "동일 사유로 2회 이상 반려된 경우 {owner}에 직접 문의하시기 바랍니다."),
    ("유의사항", "제도를 이용하실 때 다음 사항에 유의해 주시기 바랍니다.\n"
                 "  · 신청 기한: 사유 발생일로부터 {deadline}일 이내에 신청해야 하며, "
                 "기한 경과 시 {penalty}\n"
                 "  · 증빙 원칙: 모든 증빙은 원본 또는 원본대조필 사본이어야 합니다. "
                 "전자 영수증은 발행처가 확인 가능한 형태여야 합니다.\n"
                 "  · 부정 수급: 허위 신청이 확인된 경우 지급액 전액 환수 및 "
                 "징계규정에 따른 조치가 이루어집니다.\n"
                 "  · 중복 지원: 동일 사유로 타 제도의 지원을 받은 경우 중복 지원되지 않습니다.\n"
                 "  · 개인정보: 신청 과정에서 수집되는 정보는 제도 운영 목적으로만 사용되며 "
                 "관련 법령이 정한 기간 동안 보관 후 파기합니다."),
    ("자주 묻는 질문", "Q1. 중도 입사자도 신청할 수 있나요?\n"
                       "A1. 가능합니다. 다만 입사일 기준으로 월할 계산하여 한도가 정해집니다.\n\n"
                       "Q2. 미사용분이 이월되나요?\n"
                       "A2. {carryover}\n\n"
                       "Q3. 퇴직 시 미사용분은 어떻게 되나요?\n"
                       "A3. {onexit}\n\n"
                       "Q4. 배우자도 같은 회사에 근무하는 경우 각각 신청할 수 있나요?\n"
                       "A4. {spouse}\n\n"
                       "Q5. 신청 후 취소할 수 있나요?\n"
                       "A5. 사용 개시 전까지는 {system}에서 직접 취소할 수 있습니다. "
                       "사용 개시 후에는 {owner}에 문의하시기 바랍니다.\n\n"
                       "Q6. 이의가 있는 경우 어떻게 하나요?\n"
                       "A6. 결과 통보일로부터 7일 이내에 {channel}을(를) 통해 이의를 제기할 수 있습니다."),
    ("관련 규정 및 문의", "이 안내서는 다음 규정에 근거합니다.\n"
                          "  · {rule1}\n  · {rule2}\n  · 근로기준법 및 관계 법령\n\n"
                          "규정과 이 안내서의 내용이 다른 경우 규정이 우선합니다. "
                          "안내서는 이해를 돕기 위한 참고자료이며 법적 효력을 갖지 않습니다.\n\n"
                          "문의처\n  · 담당: {owner}\n  · 채널: {channel}\n"
                          "  · 처리 시간: 평일 09:00~18:00 (점심시간 12:00~13:00 제외)\n"
                          "  · 긴급 문의: 내선 {ext}"),
]


def gen_longform(corpus, rnd, n=220):
    """장문 매뉴얼 — 여러 절로 구성되어 반드시 청킹이 필요한 문서."""
    for i in range(n):
        category, sub, leaf = pick(rnd, FLAT_TOPICS)
        published = d(-rnd.randint(30, 1200))

        sections = []
        for idx, (heading, tmpl) in enumerate(LONGFORM_SECTIONS, start=1):
            amounts = {f"{c}{r}": money(rnd, 100000, 5000000, 100000)
                       for c in "abcd" for r in "1234"}
            sections.append(
                f"\n\n{idx}. {heading}\n" + "-" * 40 + "\n" +
                tmpl.format(
                    COMPANY=COMPANY, topic=leaf,
                    purpose=rnd.choice(["일·생활 균형", "역량 개발", "건강 증진",
                                        "업무 몰입", "장기 근속"]),
                    year=rnd.randint(2015, 2024), count=rnd.randint(1, 8),
                    last=d(-rnd.randint(60, 900)),
                    goal1=f"{leaf} 이용의 형평성 확보",
                    goal2=f"{leaf} 관련 업무 절차의 간소화",
                    goal3=f"{leaf} 운영 현황의 투명한 공개",
                    owner=owner_for(category),
                    role=rnd.choice(["인사", "총무", "노무", "안전"]),
                    emp1=EMPLOYMENT_TYPES[0], emp2=pick(rnd, EMPLOYMENT_TYPES[1:]),
                    tenure=rnd.choice(["3개월", "6개월", "1년"]),
                    probation=rnd.choice(["적용 제외", "50% 한도로 적용", "부서장 승인 시 적용"]),
                    onleave=rnd.choice(["복직 후 적용", "휴직 기간 중 정지",
                                        "육아휴직에 한해 적용"]),
                    after=rnd.choice(["3개월", "6개월", "1년"]),
                    system=pick(rnd, SYSTEMS), menu=f"{sub} > {leaf}",
                    form=pick(rnd, FORMS),
                    evidence=", ".join(pick(rnd, EVIDENCE, 3)),
                    approver=pick(rnd, APPROVERS), days=rnd.randint(1, 7),
                    channel=pick(rnd, CHANNELS),
                    deadline=rnd.choice([7, 14, 30, 60]),
                    penalty=rnd.choice(["소급 적용되지 않습니다.",
                                        "부서장 승인이 별도로 필요합니다.",
                                        "차기 회차로 이월됩니다."]),
                    carryover=rnd.choice(["최대 1회, 다음 연도 3월까지 이월 가능합니다.",
                                          "이월되지 않으며 매년 소멸됩니다.",
                                          "50% 범위에서 이월 가능합니다."]),
                    onexit=rnd.choice(["미사용분은 정산하여 최종 급여에 반영합니다.",
                                       "미사용분은 소멸되며 정산 대상이 아닙니다."]),
                    spouse=rnd.choice(["각각 신청 가능합니다.",
                                       "부부 합산 한도가 적용되어 1인만 신청할 수 있습니다."]),
                    rule1=pick(rnd, [b[0] for b in RULE_BOOKS]),
                    rule2=pick(rnd, [b[0] for b in RULE_BOOKS]),
                    ext=rnd.randrange(1000, 9999),
                    **amounts,
                )
            )

        corpus.add(
            "MAN",
            title=f"{leaf} 운영 매뉴얼 ({published[:4]}년판)",
            content=(
                f"{COMPANY_FULL}\n{leaf} 운영 매뉴얼\n"
                f"발행: {owner_for(category)} / 발행일: {published} / 문서번호: MAN-{i+1:04d}"
                + "".join(sections)
            ),
            category=category,
            subcategory=sub,
            topic=leaf,
            doc_type="매뉴얼",
            doc_group=f"{sub} 매뉴얼",
            version=f"{rnd.randint(1, 4)}.{rnd.randint(0, 9)}",
            status=rnd.choices(STATUSES, weights=[0.9, 0.07, 0.03])[0],
            effective_date=published,
            expiry_date=None,
            owner_dept=owner_for(category),
            audience=pick(rnd, AUDIENCES, rnd.randint(1, 2)),
            security_level=rnd.choices(SECURITY_LEVELS, weights=[0.2, 0.75, 0.05])[0],
            keywords=[leaf, sub, "매뉴얼", "운영"],
            source_uri=f"{INTRANET}/manuals/MAN-{i+1:04d}.pdf",
            updated_at=published,
        )


# ═══════════════════════════════════════════════════════════ 9. 함정 데이터
#
# ★ 여기가 이 생성기의 핵심이다.
#   무작위 문서 1만 건은 «검색이 되는지»만 보여 준다.
#   틀리기 쉬운 경우를 «의도적으로» 심어야 «어떤 검색 전략이 왜 필요한지»가 드러난다.

def gen_traps(corpus, rnd):
    trap_ids = {k: [] for k in TRAPS}

    # ── 함정 1. 버전 충돌 — 구버전(폐지) vs 신버전(현행)
    for topic in TRAPS["version_conflict"]["대상"]:
        category = "인사" if topic in ("연차휴가", "재택근무", "성과급") else "총무"
        sub = next((s for s, leaves in TAXONOMY[category].items()
                    if any(topic in l or l in topic for l in leaves)), "휴가")
        old_val, new_val = rnd.randint(5, 12), rnd.randint(15, 25)

        old = corpus.add(
            "TRP",
            title=f"{topic} 운영기준 (구버전)",
            content=(
                f"[폐지] {topic} 운영기준 v1.0\n\n"
                f"{topic}의 한도는 연 {old_val}일로 한다.\n"
                f"신청은 사유 발생 7일 전까지 하여야 한다.\n\n"
                f"※ 이 문서는 2025-12-31자로 폐지되었습니다. v2.0을 참고하십시오."
            ),
            category=category, subcategory=sub, topic=topic,
            doc_type="규정", doc_group=f"{topic} 운영기준",
            version="1.0", status="폐지",
            effective_date="2023-01-01", expiry_date="2025-12-31",
            owner_dept=owner_for(category), audience=["전직원"],
            security_level="사내", keywords=[topic, "구버전", "폐지"],
            source_uri=f"{INTRANET}/rules/{topic}/v1",
            updated_at="2025-12-31",
            trap="version_conflict", trap_role="구버전",
        )
        new = corpus.add(
            "TRP",
            title=f"{topic} 운영기준 (현행)",
            content=(
                f"[현행] {topic} 운영기준 v2.0\n\n"
                f"{topic}의 한도는 연 {new_val}일로 한다.\n"
                f"신청은 사유 발생 3일 전까지 하면 된다.\n"
                f"직전 v1.0 대비 한도가 {old_val}일에서 {new_val}일로 확대되었다.\n\n"
                f"시행일: 2026-01-01"
            ),
            category=category, subcategory=sub, topic=topic,
            doc_type="규정", doc_group=f"{topic} 운영기준",
            version="2.0", status="현행",
            effective_date="2026-01-01", expiry_date=None,
            owner_dept=owner_for(category), audience=["전직원"],
            security_level="사내", keywords=[topic, "현행", "개정"],
            source_uri=f"{INTRANET}/rules/{topic}/v2",
            updated_at="2026-01-01",
            trap="version_conflict", trap_role="현행",
            answer_value=f"{new_val}일",
        )
        trap_ids["version_conflict"].append(
            {"topic": topic, "정답": new["doc_id"], "오답": old["doc_id"],
             "정답값": f"{new_val}일", "오답값": f"{old_val}일"})

    # ── 함정 2. 근사 중복 — 두 규정에 거의 같은 문장
    for topic in TRAPS["near_duplicate"]["대상"]:
        base = (f"직원의 소정근로시간은 1일 8시간, 1주 40시간으로 한다. "
                f"휴게시간은 4시간 근무 시 30분, 8시간 근무 시 1시간을 부여한다. "
                f"{topic}에 관하여 이 규정에서 정하지 아니한 사항은 근로기준법을 따른다.")
        ids = []
        for book in ["인사규정", "취업규칙"]:
            rec = corpus.add(
                "TRP",
                title=f"{book} - {topic} 조항",
                content=f"[{book}]\n{base}\n(출처: {book})",
                category="인사", subcategory="근태", topic=topic,
                doc_type="규정", doc_group=book,
                version="3.0", status="현행",
                effective_date="2025-07-01", expiry_date=None,
                owner_dept="인사팀", audience=["전직원"],
                security_level="사내", keywords=[topic, "근로시간", book],
                source_uri=f"{INTRANET}/rules/{book}/{topic}",
                updated_at="2025-07-01",
                trap="near_duplicate", trap_role=book,
            )
            ids.append(rec["doc_id"])
        trap_ids["near_duplicate"].append({"topic": topic, "중복문서": ids})

    # ── 함정 3. 숫자 정밀도 — 벡터만으로는 못 잡는다
    numeric_facts = [
        ("연차휴가 일수", "인사", "휴가", "입사 1년 미만은 월 1일, 1년 이상은 15일, "
                                      "3년 이상은 2년마다 1일씩 가산하여 최대 25일"),
        ("경조휴가 일수", "인사", "휴가", "본인 결혼 5일, 자녀 결혼 1일, 배우자 출산 10일, "
                                      "부모 사망 5일, 조부모 사망 2일"),
        ("출장 숙박비 한도", "총무", "출장", "국내 서울 12만원, 광역시 10만원, 그 외 8만원. "
                                        "해외는 A급지 25만원, B급지 18만원, C급지 12만원"),
        ("식대 한도", "총무", "복리후생", "중식 1인 1만원, 석식 1만 5천원(20시 이후 근무 시), "
                                     "회식 1인 5만원(분기 1회)"),
        ("교육비 지원 한도", "인사", "교육", "직무교육 연 200만원, 어학 연 120만원, "
                                        "자격증 회당 50만원(연 2회), 학위과정 연 500만원"),
    ]
    for title, category, sub, detail in numeric_facts:
        rec = corpus.add(
            "TRP",
            title=f"{title} 기준표",
            content=f"■ {title}\n\n{detail}\n\n"
                    f"※ 위 금액은 세전 기준이며, 증빙 제출 시 실비 정산합니다.\n"
                    f"근거: {'인사규정' if category == '인사' else '총무규정'}",
            category=category, subcategory=sub, topic=title,
            doc_type="안내서", doc_group="기준표",
            version="2026.1", status="현행",
            effective_date="2026-01-01", expiry_date=None,
            owner_dept=owner_for(category), audience=["전직원"],
            security_level="사내", keywords=[title, sub, "기준", "한도"],
            source_uri=f"{INTRANET}/standards/{title}",
            updated_at="2026-01-01",
            trap="numeric_precision", trap_role="정답",
        )
        trap_ids["numeric_precision"].append({"topic": title, "정답": rec["doc_id"]})

    # ── 함정 4. 다중 홉 — 조각을 여러 문서에 흩어 놓는다
    multi_hop_sets = [
        {
            "질문": "3년차 개발직이 육아휴직을 쓰면 급여와 평가는 어떻게 되나요?",
            "조각": [
                ("육아휴직 급여 처리", "인사", "휴직",
                 "육아휴직 기간 중 회사 급여는 지급하지 않는다. "
                 "고용보험 육아휴직급여를 신청할 수 있으며, 회사는 최초 3개월간 "
                 "통상임금의 20%를 추가 지원한다."),
                ("휴직자 인사평가 처리", "인사", "평가",
                 "휴직 기간이 평가 기간의 절반을 초과하는 경우 해당 기간 평가를 유예한다. "
                 "절반 이하인 경우 실근무 기간에 대해 평가하되 등급 배분에서 제외한다."),
                ("육아휴직 신청 자격", "인사", "휴직",
                 "재직 6개월 이상인 직원은 만 12세 이하 자녀 1명당 최대 1년간 신청할 수 있다. "
                 "직군·직급에 따른 제한은 없다."),
            ],
        },
        {
            "질문": "해외출장 중 주말에 근무하면 수당과 대체휴무는 어떻게 되나요?",
            "조각": [
                ("해외출장 중 휴일근로", "총무", "출장",
                 "해외출장 중 휴일에 업무를 수행한 경우 출장 종료 후 30일 이내에 "
                 "대체휴무를 신청할 수 있다. 사전 승인이 있어야 인정된다."),
                ("휴일근로수당 기준", "인사", "급여",
                 "휴일근로는 통상임금의 150%를 지급한다. 8시간을 초과하는 부분은 200%를 적용한다. "
                 "다만 대체휴무를 사용한 경우 수당은 중복 지급하지 않는다."),
                ("해외출장 일비 기준", "총무", "출장",
                 "해외출장 일비는 A급지 8만원, B급지 6만원, C급지 4만원이며 휴일도 동일하게 지급한다."),
            ],
        },
        {
            "질문": "퇴직할 때 미사용 연차와 퇴직연금은 각각 어떻게 처리되나요?",
            "조각": [
                ("퇴직 시 연차 정산", "인사", "퇴직",
                 "퇴직일 기준 미사용 연차는 통상임금 기준으로 수당 정산하여 "
                 "최종 급여 지급일에 함께 지급한다."),
                ("퇴직연금 수령 방법", "인사", "보험",
                 "퇴직연금은 IRP 계좌로만 이전 가능하다. 퇴직일로부터 14일 이내에 "
                 "IRP 계좌 정보를 제출하여야 하며, 미제출 시 지급이 지연된다."),
                ("퇴직 절차 일정", "인사", "퇴직",
                 "사직서는 퇴직 희망일 30일 전에 제출한다. 자산 반납과 인수인계 확인서 제출 후 "
                 "최종 승인되며, 급여 정산은 퇴직월 급여일에 이루어진다."),
            ],
        },
    ]
    for hop in multi_hop_sets:
        ids = []
        for title, category, sub, detail in hop["조각"]:
            rec = corpus.add(
                "TRP",
                title=title,
                content=f"■ {title}\n\n{detail}\n\n담당: {owner_for(category)}",
                category=category, subcategory=sub, topic=title,
                doc_type="지침", doc_group="다중홉 대상",
                version="1.0", status="현행",
                effective_date="2026-01-01", expiry_date=None,
                owner_dept=owner_for(category), audience=["전직원"],
                security_level="사내", keywords=[title, sub],
                source_uri=f"{INTRANET}/guides/{title}",
                updated_at="2026-01-01",
                trap="multi_hop", trap_role="조각",
            )
            ids.append(rec["doc_id"])
        trap_ids["multi_hop"].append({"질문": hop["질문"], "필요문서": ids})

    # ── 함정 5. 권한 제한 문서
    restricted = [
        ("징계 양정 기준표", "인사", "노무", "인사담당자",
         "징계 종류별 양정 기준: 견책(경미한 복무위반), 감봉(반복 위반), "
         "정직(중대 과실), 해임(고의적 손해), 파면(형사처벌 대상)"),
        ("직급별 급여 테이블", "인사", "급여", "인사담당자",
         "직급별 기본급 밴드: 사원 3,200~3,800만원, 선임 3,900~4,800만원, "
         "책임 4,900~6,500만원, 수석 6,600~8,500만원"),
        ("평가등급 배분 비율", "인사", "평가", "관리자",
         "S 10%, A 20%, B 50%, C 15%, D 5%. 부서별 강제 배분 적용."),
        ("명예퇴직 지원 기준", "인사", "퇴직", "인사담당자",
         "근속 15년 이상, 만 50세 이상 대상. 위로금은 잔여 정년 개월 수 × 통상임금 × 0.6"),
    ]
    for title, category, sub, aud, detail in restricted:
        rec = corpus.add(
            "TRP",
            title=title,
            content=f"[제한] {title}\n\n{detail}\n\n"
                    f"※ 이 문서는 {aud} 전용입니다. 무단 열람·공유를 금합니다.",
            category=category, subcategory=sub, topic=title,
            doc_type="규정", doc_group="제한 문서",
            version="2026.1", status="현행",
            effective_date="2026-01-01", expiry_date=None,
            owner_dept="인사팀", audience=[aud],
            security_level="제한", keywords=[title, sub, "제한"],
            source_uri=f"{INTRANET}/restricted/{title}",
            updated_at="2026-01-01",
            trap="permission_scoped", trap_role="제한문서",
        )
        trap_ids["permission_scoped"].append(
            {"topic": title, "문서": rec["doc_id"], "허용대상": aud})

    return trap_ids


# ═══════════════════════════════════════════════════════════ 실행

def main():
    ap = argparse.ArgumentParser(description="인사·총무 가상 지식 코퍼스 생성기")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "data"))
    ap.add_argument("--seed", type=int, default=20260829,
                    help="재현 가능한 생성을 위한 난수 시드")
    ap.add_argument("--faq", type=int, default=3600)
    ap.add_argument("--tickets", type=int, default=4000)
    ap.add_argument("--notices", type=int, default=1200)
    ap.add_argument("--procedures", type=int, default=140)
    ap.add_argument("--forms", type=int, default=400)
    ap.add_argument("--handbooks", type=int, default=900)
    ap.add_argument("--manuals", type=int, default=220,
                    help="장문 매뉴얼 — 청킹 검증에 반드시 필요하다")
    args = ap.parse_args()

    rnd = random.Random(args.seed)
    corpus = Corpus()

    print("=" * 68)
    print(f" {COMPANY} 인사·총무 가상 지식 코퍼스 생성")
    print("=" * 68)
    print(f" 시드 {args.seed} — 같은 시드는 같은 결과를 만든다")
    print()

    gen_rules(corpus, rnd)
    print(f"  규정      {sum(1 for x in corpus.docs if x['doc_type'] == '규정'):>6,}건")

    gen_procedures(corpus, rnd, args.procedures)
    print(f"  지침      {sum(1 for x in corpus.docs if x['doc_type'] == '지침'):>6,}건")

    made = gen_faq(corpus, rnd, args.faq)
    print(f"  FAQ       {made:>6,}건")

    gen_tickets(corpus, rnd, args.tickets)
    print(f"  문의이력  {args.tickets:>6,}건")

    gen_notices(corpus, rnd, args.notices)
    print(f"  공지      {args.notices:>6,}건")

    gen_forms(corpus, rnd, args.forms)
    print(f"  서식안내  {args.forms:>6,}건")

    gen_handbooks(corpus, rnd, args.handbooks)
    print(f"  안내서    {args.handbooks:>6,}건")

    gen_full_rulebooks(corpus, rnd)
    n_full = sum(1 for x in corpus.docs if x["doc_type"] == "규정전문")
    print(f"  규정전문  {n_full:>6,}건  ← 장문. 반드시 청킹이 필요한 문서")

    gen_longform(corpus, rnd, args.manuals)
    print(f"  매뉴얼    {args.manuals:>6,}건  ← 장문. 절 단위 청킹 대상")

    traps = gen_traps(corpus, rnd)
    n_trap = sum(1 for x in corpus.docs if x.get("trap"))
    print(f"  함정      {n_trap:>6,}건  ← 의도적으로 심은 «틀리기 쉬운» 데이터")

    # ── 언어 품질 검증 — 미해결 조사가 남아 있으면 실패로 본다
    unresolved = []
    for doc in corpus.docs:
        found = check_unresolved(doc["content"]) + check_unresolved(doc["title"])
        if found:
            unresolved.append((doc["doc_id"], found[:3]))

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    # ── 코퍼스 (JSONL)
    corpus_path = os.path.join(out_dir, "corpus.jsonl")
    with io.open(corpus_path, "w", encoding="utf-8", newline="\n") as f:
        for doc in corpus.docs:
            f.write(json.dumps(doc, ensure_ascii=False) + "\n")

    # ── 함정 정답 키 — 평가 세트를 만들 때 쓴다
    traps_path = os.path.join(out_dir, "traps.json")
    with io.open(traps_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"설명": {k: v["설명"] for k, v in TRAPS.items()},
                   "검증": {k: v["검증"] for k, v in TRAPS.items()},
                   "데이터": traps},
                  f, ensure_ascii=False, indent=2)

    # ── 통계
    lengths = [len(x["content"]) for x in corpus.docs]
    lengths.sort()
    by_type, by_cat, by_status, by_sec = {}, {}, {}, {}
    for x in corpus.docs:
        by_type[x["doc_type"]] = by_type.get(x["doc_type"], 0) + 1
        by_cat[x["category"]] = by_cat.get(x["category"], 0) + 1
        by_status[x["status"]] = by_status.get(x["status"], 0) + 1
        by_sec[x["security_level"]] = by_sec.get(x["security_level"], 0) + 1

    stats = {
        "생성일": TODAY.isoformat(),
        "시드": args.seed,
        "총건수": len(corpus.docs),
        "총문자수": sum(lengths),
        "문자수": {
            "최소": lengths[0], "최대": lengths[-1],
            "중앙값": lengths[len(lengths) // 2],
            "평균": round(sum(lengths) / len(lengths), 1),
            "p90": lengths[int(len(lengths) * 0.9)],
            "p99": lengths[int(len(lengths) * 0.99)],
        },
        "문서유형별": dict(sorted(by_type.items(), key=lambda kv: -kv[1])),
        "대분류별": by_cat,
        "상태별": by_status,
        "보안등급별": by_sec,
        "중분류수": len(set((x["category"], x["subcategory"]) for x in corpus.docs)),
        "세부주제수": len(set(x["topic"] for x in corpus.docs)),
        "함정건수": n_trap,
        "미해결조사": len(unresolved),
        "청킹필요": {
            "설명": "1,000자를 넘어 분할이 필요한 문서 수",
            "임계값": 1000,
            "건수": sum(1 for x in corpus.docs if len(x["content"]) > 1000),
            "비율": round(sum(1 for x in corpus.docs if len(x["content"]) > 1000)
                         / len(corpus.docs) * 100, 2),
            "장문_총문자수": sum(len(x["content"]) for x in corpus.docs
                              if len(x["content"]) > 1000),
        },
    }
    stats_path = os.path.join(out_dir, "corpus_stats.json")
    with io.open(stats_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)

    print()
    print("-" * 68)
    if unresolved:
        print(f"  ✗ 미해결 조사 {len(unresolved)}건 — 예: {unresolved[:3]}")
    else:
        print("  ✓ 조사 표기 정상 (미해결 «~(는)» 0건)")
    print(f"  총 {len(corpus.docs):,}건 · {sum(lengths):,}자")
    print(f"  길이 중앙값 {stats['문자수']['중앙값']:,}자 · "
          f"p90 {stats['문자수']['p90']:,}자 · 최대 {stats['문자수']['최대']:,}자")
    print(f"  중분류 {stats['중분류수']}개 · 세부주제 {stats['세부주제수']}개")
    print()
    print(f"  → {corpus_path}")
    print(f"  → {traps_path}")
    print(f"  → {stats_path}")
    print()
    if len(corpus.docs) < 10000:
        print("  ⚠️ 목표(1만 건)에 미달합니다. --faq / --tickets 값을 올리세요.")
        return 1
    print("  ✓ 목표 1만 건 이상 충족")
    return 0


if __name__ == "__main__":
    sys.exit(main())
