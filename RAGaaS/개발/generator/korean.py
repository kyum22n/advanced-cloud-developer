# -*- coding: utf-8 -*-
"""한국어 조사 처리 — «~은(는)» 을 실제 조사로 확정한다.

왜 필요한가
    템플릿으로 문장을 만들면 «육아휴직은(는)», «부문장이(가)» 같은 표기가 남는다.
    사람이 읽기 나쁠 뿐 아니라, RAG 실험 데이터로서 두 가지 실질적 문제가 있다.

    ① 임베딩 품질   «은(는)» 은 실제 한국어에 없는 토큰 조합이다.
                     토크나이저가 이를 이상하게 쪼개면 문장 벡터가 왜곡된다.
    ② BM25 매칭     «접대비은(는)» 은 «접대비» 와 다른 토큰이 되어
                     키워드 검색의 재현율을 떨어뜨린다.

    합성 데이터라도 «언어적으로 정상»이어야 실험 결과를 믿을 수 있다.

규칙
    받침(종성)이 있으면 은/이/을/과/으로, 없으면 는/가/를/와/로.
    'ㄹ' 받침은 예외로 «로» 를 쓴다 (예: 서울로, 개발로).
"""
import re

# 한글 음절: 0xAC00 + (초성×588) + (중성×28) + 종성
HANGUL_BASE = 0xAC00
HANGUL_LAST = 0xD7A3

# 숫자·영문의 «읽는 소리» 기준 받침 유무.
# 예: 1(일)→받침O, 2(이)→받침X, 3(삼)→받침O …
DIGIT_HAS_FINAL = {
    "0": True,   # 영
    "1": True,   # 일
    "2": False,  # 이
    "3": True,   # 삼
    "4": False,  # 사
    "5": False,  # 오
    "6": True,   # 육
    "7": True,   # 칠
    "8": True,   # 팔
    "9": False,  # 구
}

# 영문 알파벳을 한국어로 읽었을 때의 받침 유무 (예: L→엘(받침O), A→에이(받침X))
ALPHA_HAS_FINAL = {
    "a": False, "b": False, "c": False, "d": False, "e": False, "f": False,
    "g": False, "h": False, "i": False, "j": False, "k": False, "l": True,
    "m": True,  "n": True,  "o": False, "p": False, "q": False, "r": True,
    "s": False, "t": False, "u": False, "v": False, "w": False, "x": False,
    "y": False, "z": False,
}


def has_final_consonant(word):
    """단어의 마지막 «소리»에 받침이 있는가.

    괄호·따옴표 등 발음되지 않는 기호는 건너뛰고 마지막 실제 글자를 본다.

    Returns:
        (받침 있음 여부, 'ㄹ' 받침 여부). 판별 불가하면 (None, False).
    """
    for ch in reversed(word):
        code = ord(ch)
        if HANGUL_BASE <= code <= HANGUL_LAST:
            final = (code - HANGUL_BASE) % 28
            # 종성 인덱스 8 == 'ㄹ'
            return final != 0, final == 8
        if ch.isdigit():
            return DIGIT_HAS_FINAL[ch], ch == "1"        # 일 → ㄹ 받침
        if ch.isalpha() and ch.isascii():
            return ALPHA_HAS_FINAL[ch.lower()], ch.lower() in ("l", "r")
        # 그 외 기호는 발음되지 않으므로 계속 앞으로 간다
    return None, False


# «단어 + 조사 + (대체조사)» 를 찾는다.
#
# ⚠️ 단어 부분을 탐욕적으로 잡으면 «육아휴직은» 까지 삼켜 «육아휴직은은» 이 된다.
#    비탐욕(+?)으로 두어 «육아휴직» + «은» + «(는)» 으로 갈라지게 한다.
#    또한 대안 순서를 «긴 것 먼저»로 두어야 «으로» 가 «로» 에 가려지지 않는다.
_JOSA_ALTS = r"으로|이라|이나|은|는|이|가|을|를|과|와|로|나|라|아|야"

_JOSA_PATTERN = re.compile(
    r"([가-힣A-Za-z0-9\)\]\}»\"']+?)"      # 단어 (비탐욕)
    r"(" + _JOSA_ALTS + r")"               # 붙어 있는 조사
    r"\((" + _JOSA_ALTS + r")\)"           # 괄호 안 대체 조사
)

# (앞표기, 뒤표기) — 받침 있을 때 / 없을 때
_PAIRS = {
    "은": ("은", "는"), "는": ("은", "는"),
    "이": ("이", "가"), "가": ("이", "가"),
    "을": ("을", "를"), "를": ("을", "를"),
    "과": ("과", "와"), "와": ("과", "와"),
    "으로": ("으로", "로"), "로": ("으로", "로"),
    "이나": ("이나", "나"), "나": ("이나", "나"),
    "이라": ("이라", "라"), "라": ("이라", "라"),
    "아": ("아", "야"), "야": ("아", "야"),
}


def resolve_josa(text):
    """«단어은(는)» → «단어는» 으로 확정한다.

    >>> resolve_josa("육아휴직은(는) 팀장의 승인")
    '육아휴직은 팀장의 승인'
    >>> resolve_josa("접대비은(는) 누리ERP에서")
    '접대비는 누리ERP에서'
    >>> resolve_josa("부문장이(가) 연장할 수 있다")
    '부문장이 연장할 수 있다'
    >>> resolve_josa("서울으로(로) 이동")
    '서울로 이동'
    """
    def repl(m):
        word, attached, alternative = m.group(1), m.group(2), m.group(3)
        # 붙은 조사와 괄호 안 조사는 같은 짝이므로 어느 쪽으로 찾아도 된다
        key = attached if attached in _PAIRS else alternative
        if key not in _PAIRS:
            return m.group(0)

        with_final, is_rieul = has_final_consonant(word)
        if with_final is None:
            # 판별할 수 없으면 원문을 그대로 둔다. 틀린 조사를 붙이는 것보다 낫다.
            return m.group(0)

        a, b = _PAIRS[key]
        # 'ㄹ' 받침 뒤에서는 «으로» 가 아니라 «로» 를 쓴다
        if key in ("으로", "로") and is_rieul:
            return word + "로"
        return word + (a if with_final else b)

    return _JOSA_PATTERN.sub(repl, text)


def check_unresolved(text):
    """미해결 «(는)» 표기가 남아 있으면 목록으로 돌려준다. 검증용."""
    return re.findall(r"[가-힣A-Za-z0-9]+\s*\((?:은|는|이|가|을|를|과|와|으로|로)\)", text)


if __name__ == "__main__":
    import io
    import sys
    if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

    cases = [
        ("육아휴직은(는) 팀장의 승인을 받는다", "육아휴직은 팀장의 승인을 받는다"),
        ("접대비은(는) 누리ERP에서 신청", "접대비는 누리ERP에서 신청"),
        ("부문장이(가) 연장할 수 있다", "부문장이 연장할 수 있다"),
        ("연차휴가이(가) 확대되었다", "연차휴가가 확대되었다"),
        ("규정을(를) 참고하세요", "규정을 참고하세요"),
        ("절차를(을) 따른다", "절차를 따른다"),
        ("서울으로(로) 이동", "서울로 이동"),
        ("본사으로(로) 이동", "본사로 이동"),
        ("판교로(으로) 이동", "판교로 이동"),
        ("2일이(가) 추가된다", "2일이 추가된다"),
        ("3회을(를) 초과", "3회를 초과"),
        ("IRP을(를) 개설", "IRP를 개설"),
        ("WFH이(가) 허용", "WFH가 허용"),
    ]
    ok = 0
    for src, want in cases:
        got = resolve_josa(src)
        mark = "✓" if got == want else "✗"
        if got == want:
            ok += 1
        else:
            print(f"  {mark} {src!r}\n      기대 {want!r}\n      실제 {got!r}")
    print(f"\n조사 처리 {ok}/{len(cases)} 통과")
    sys.exit(0 if ok == len(cases) else 1)
