# -*- coding: utf-8 -*-
"""RAGaaS 산출물 최종 검증 — 링크 무결성 · 파일 존재 · 통계 일관성"""
import io, json, os, re, sys, glob
if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1
                       else os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
fail = 0

def ok(c, msg):
    global fail
    print(("   OK  " if c else "   FAIL") + " " + msg)
    if not c: fail += 1

print("=" * 72)
print(" RAGaaS 최종 검증")
print("=" * 72)

# 1. 필수 산출물
print("\n[1] 필수 산출물")
required = [
    "README.md", "00_단계별_실습_프롬프트.md",
    "개발/README.md", "테스트/README.md",
    "개발/playground/시연_시나리오.md",
    "개발/generator/taxonomy.py", "개발/generator/korean.py",
    "개발/generator/generate_corpus.py",
    "개발/pipeline/chunker.py", "개발/pipeline/embed.py",
    "개발/search/hybrid.py", "개발/search/agentic.py",
    "개발/config/build_azure_config.py", "개발/config/deploy_index.py",
    "개발/config/.env.example",
    "테스트/goldenset/build_goldenset.py", "테스트/eval/eval_retrieval.py",
    "개발/data/corpus.jsonl", "개발/data/chunks.jsonl",
    "개발/data/vectors.npz", "개발/data/traps.json",
    "테스트/goldenset/goldenset.json", "테스트/eval/eval_result_k5.json",
]
missing = [p for p in required if not os.path.exists(os.path.join(ROOT, p))]
ok(not missing, "필수 파일 %d개" % len(required) + ("" if not missing else " — 없음: " + ", ".join(missing)))
for n, pat in (("분석", "분석/*.md"), ("설계", "설계/*.md")):
    got = sorted(glob.glob(os.path.join(ROOT, pat)))
    exp = 7 if n == "분석" else 12
    ok(len(got) == exp, "%s 문서 %d편 (기대 %d)" % (n, len(got), exp))

# 2. JSON 파싱
print("\n[2] JSON 파싱")
bad = []
for f in glob.glob(os.path.join(ROOT, "**", "*.json"), recursive=True):
    try: json.load(io.open(f, encoding="utf-8"))
    except Exception as e: bad.append((os.path.relpath(f, ROOT), str(e)[:60]))
ok(not bad, "JSON 파일 파싱 " + ("전부 정상" if not bad else "실패: %s" % bad))

# 3. 링크 무결성
print("\n[3] 마크다운 링크")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
broken, total = [], 0
for md in glob.glob(os.path.join(ROOT, "**", "*.md"), recursive=True):
    base = os.path.dirname(md)
    for href in LINK.findall(io.open(md, encoding="utf-8").read()):
        if href.startswith(("http://", "https://", "#", "mailto:")): continue
        total += 1
        target = os.path.normpath(os.path.join(base, href.split("#")[0]))
        if not os.path.exists(target):
            broken.append("%s → %s" % (os.path.relpath(md, ROOT), href))
ok(not broken, "내부 링크 %d개" % total + ("" if not broken else " — 깨짐 %d: %s" % (len(broken), broken[:5])))

# 4. 통계 일관성
print("\n[4] 통계 일관성")
cs = json.load(io.open(os.path.join(ROOT, "개발/data/corpus_stats.json"), encoding="utf-8"))
ks = json.load(io.open(os.path.join(ROOT, "개발/data/chunk_stats.json"), encoding="utf-8"))
def dig(d, *names):
    for n in names:
        if n in d: return d[n]
    for v in d.values():
        if isinstance(v, dict):
            r = dig(v, *names)
            if r is not None: return r
    return None
n_doc = dig(cs, "총건수", "문서수", "총문서수", "count", "total")
n_chunk = dig(ks, "총청크수", "청크수", "총건수", "count", "total")
over = dig(ks, "상한초과", "상한_초과", "over_max")
ok(isinstance(n_doc, int) and n_doc >= 10000, "코퍼스 %s건 (요구 1만 이상)" % n_doc)
ok(isinstance(n_chunk, int) and n_chunk >= n_doc, "청크 %s건 (문서 이상)" % n_chunk)
ok(over == 0, "청크 상한 초과 %s건" % over)

nl = lambda p: sum(1 for _ in io.open(os.path.join(ROOT, p), encoding="utf-8"))
ok(nl("개발/data/corpus.jsonl") == n_doc, "corpus.jsonl 줄 수 = 통계 문서 수")
ok(nl("개발/data/chunks.jsonl") == n_chunk, "chunks.jsonl 줄 수 = 통계 청크 수")

try:
    import numpy as np
    z = np.load(os.path.join(ROOT, "개발/data/vectors.npz"))
    v = z[z.files[0]]
    ok(v.shape[0] == n_chunk, "벡터 %d개 = 청크 수 (차원 %d)" % (v.shape[0], v.shape[1]))
except Exception as e:
    ok(False, "vectors.npz 확인 실패: %s" % e)

gs = json.load(io.open(os.path.join(ROOT, "테스트/goldenset/goldenset.json"), encoding="utf-8"))
cases = gs.get("사례") or gs.get("cases") or (gs if isinstance(gs, list) else [])
ok(len(cases) >= 30, "평가 세트 %d건" % len(cases))
kinds = {c.get("유형", c.get("type")) for c in cases}
ok(len(kinds) == 7, "질의 유형 %d종: %s" % (len(kinds), sorted(k for k in kinds if k)))

ev = json.load(io.open(os.path.join(ROOT, "테스트/eval/eval_result_k5.json"), encoding="utf-8"))
res = dig(ev, "전략별", "strategies", "결과") or ev
strat = res if isinstance(res, dict) else {}
ok(len(strat) >= 7, "평가 전략 %d종" % len(strat))

# 5. 보안 원칙
print("\n[5] 보안 원칙")
env = io.open(os.path.join(ROOT, "개발/config/.env.example"), encoding="utf-8").read()
live = [l for l in env.splitlines() if re.match(r"\s*[A-Z_]*(KEY|SECRET|PASSWORD)\s*=\s*\S", l)]
ok(not live, ".env.example 에 활성 비밀 항목 없음" + ("" if not live else " — %s" % live))

leaks = []
for f in glob.glob(os.path.join(ROOT, "**", "*.py"), recursive=True):
    txt = io.open(f, encoding="utf-8").read()
    for m in re.finditer(r"(api[_-]?key|password|secret)\s*=\s*[\"'][^\"'{}$]{8,}[\"']", txt, re.I):
        leaks.append("%s: %s" % (os.path.relpath(f, ROOT), m.group(0)[:50]))
ok(not leaks, "파이썬 코드에 하드코딩된 비밀 없음" + ("" if not leaks else " — %s" % leaks))

dep = io.open(os.path.join(ROOT, "개발/config/deploy_index.py"), encoding="utf-8").read()
ok('!= "yes"' in dep or "!= 'yes'" in dep, "배포 스크립트에 'yes' 확인 프롬프트 존재")
ok("--force" not in dep and "-Force" not in dep, "배포 스크립트에 확인 우회 플래그 없음")
ok("DefaultAzureCredential" in dep and "api-key" not in dep.lower(), "배포 인증이 관리 ID (API 키 아님)")

# 6. 데이터 안전
print("\n[6] 가상 데이터 안전")
corpus = io.open(os.path.join(ROOT, "개발/data/corpus.jsonl"), encoding="utf-8").read()
bad_dom = re.findall(r"https?://[\w.-]+", corpus)
non_example = sorted({d for d in bad_dom if ".example" not in d and "localhost" not in d})
ok(not non_example, "외부 도메인 없음" + ("" if not non_example else " — %s" % non_example[:5]))
ok("은(는)" not in corpus and "이(가)" not in corpus, "미해결 조사 표기 없음")

print("\n" + "=" * 72)
print(" 결과: " + ("전부 통과" if fail == 0 else "실패 %d건" % fail))
print("=" * 72)
sys.exit(1 if fail else 0)
