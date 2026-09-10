# -*- coding: utf-8 -*-
"""Azure AI Search 배포 — ⚠️ 실제 리소스를 만들고 과금을 시작한다.

이 스크립트는 «사람이 명시적으로 실행»해야 한다. 자동 실행되지 않는다.

배포 순서 (의존 관계가 있다)
    ① 인덱스        먼저 있어야 기술 세트의 프로젝션 대상이 된다
    ② 데이터 원본
    ③ 기술 세트     인덱스를 참조한다
    ④ 인덱서        ①②③ 을 모두 참조한다
    ⑤ 지식 원본     인덱스를 감싼다
    ⑥ 지식 베이스   지식 원본을 참조한다

⚠️ 실행 «전에» 반드시 확인할 것
    · embed.py --estimate-only 로 임베딩 규모를 확인했는가
    · config/*.json 의 자리표시자를 전부 치환했는가
    · 검색 서비스 관리 ID 에 필요한 역할이 부여되었는가
        Azure OpenAI  → Cognitive Services OpenAI User
        Blob Storage  → Storage Blob Data Reader

사용:
    python deploy_index.py --env dev --dry-run     # 무엇을 할지 «보기만»
    python deploy_index.py --env dev               # 실제 배포 (확인 프롬프트)
"""
import argparse
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

if (getattr(sys.stdout, "encoding", "") or "").lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))

API_GA = "2026-04-01"
API_PREVIEW = "2026-05-01-preview"

# (파일, 엔드포인트 경로, 이름 필드, API 버전)
RESOURCES = [
    ("index.json",            "indexes",          "name", API_GA),
    ("datasource.json",       "datasources",      "name", API_GA),
    ("skillset.json",         "skillsets",        "name", API_GA),
    ("indexer.json",          "indexers",         "name", API_GA),
    ("knowledge_source.json", "knowledgeSources", "name", API_GA),
    # 지식 베이스는 retrievalReasoningEffort 때문에 미리 보기 API 가 필요할 수 있다
    ("knowledge_base.{env}.json", "knowledgeBases", "name", API_PREVIEW),
]

PLACEHOLDER = re.compile(r"\{([A-Z_]+)\}")


def load_env():
    """환경 변수에서 치환 값을 읽는다. ⚠️ 비밀은 여기에 없다 — 주소만 있다."""
    keys = [
        "AZURE_OPENAI_RESOURCE", "EMBEDDING_DEPLOYMENT",
        "CHAT_DEPLOYMENT", "CHAT_MODEL",
        "SUBSCRIPTION_ID", "RESOURCE_GROUP", "STORAGE_ACCOUNT",
    ]
    return {k: os.environ.get(k) for k in keys}


def substitute(obj, values):
    """자리표시자를 치환하고, 남은 것을 목록으로 돌려준다."""
    missing = set()

    def walk(o):
        if isinstance(o, str):
            def repl(m):
                key = m.group(1)
                v = values.get(key)
                if not v:
                    missing.add(key)
                    return m.group(0)
                return v
            return PLACEHOLDER.sub(repl, o)
        if isinstance(o, dict):
            return {k: walk(v) for k, v in o.items()}
        if isinstance(o, list):
            return [walk(v) for v in o]
        return o

    return walk(obj), sorted(missing)


def get_token():
    """관리 ID 또는 개발자 계정 토큰. ★ API 키를 쓰지 않는다."""
    try:
        from azure.identity import DefaultAzureCredential
    except ImportError:
        raise RuntimeError(
            "azure-identity 가 필요합니다.  pip install azure-identity")
    cred = DefaultAzureCredential()
    return cred.get_token("https://search.azure.com/.default").token


def put_resource(endpoint, path, name, body, api_version, token):
    url = f"{endpoint}/{path}/{name}?api-version={api_version}"
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, method="PUT",
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return resp.status, resp.read().decode("utf-8")[:400]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")[:800]


def main():
    ap = argparse.ArgumentParser(description="Azure AI Search 배포")
    ap.add_argument("--env", choices=["dev", "stg", "prd"], default="dev")
    ap.add_argument("--dry-run", action="store_true",
                    help="무엇을 배포할지 «보기만» 한다. 아무것도 만들지 않는다")
    ap.add_argument("--only", default="",
                    help="특정 리소스만 (예: index,skillset)")
    args = ap.parse_args()

    endpoint = os.environ.get("AZURE_SEARCH_ENDPOINT")
    values = load_env()

    print("=" * 70)
    print(f" Azure AI Search 배포 — {args.env}"
          + ("  (연습 실행)" if args.dry_run else ""))
    print("=" * 70)
    print(f" 엔드포인트  {endpoint or '⚠️ AZURE_SEARCH_ENDPOINT 미설정'}")
    print()

    # ── 자리표시자 확인
    print(" 치환 값")
    all_present = True
    for k, v in values.items():
        mark = "✓" if v else "✗"
        shown = v if v else "(미설정)"
        if not v:
            all_present = False
        print(f"   {mark} {k:<26} {shown}")

    plans = []
    for filename, path, _name_field, api_version in RESOURCES:
        fname = filename.format(env=args.env)
        if args.only and path not in args.only.split(","):
            continue
        fpath = os.path.join(HERE, fname)
        if not os.path.exists(fpath):
            print(f"\n ⚠️ 파일 없음: {fname}  (build_azure_config.py 를 먼저 실행하세요)")
            continue
        body = json.load(io.open(fpath, encoding="utf-8"))
        body_sub, missing = substitute(body, values)
        # 설계 메모는 Azure 에 보내지 않는다
        body_sub.pop("_설계메모", None)
        plans.append((fname, path, body_sub["name"], body_sub, api_version, missing))

    print()
    print(" 배포 계획")
    print(f"   {'파일':<28} {'유형':<18} {'이름':<26} {'API':<20} 미치환")
    print("   " + "-" * 100)
    blocked = False
    for fname, path, name, _b, api_version, missing in plans:
        flag = f"⚠️ {','.join(missing)}" if missing else "—"
        if missing:
            blocked = True
        preview = " (미리보기)" if api_version == API_PREVIEW else ""
        print(f"   {fname:<28} {path:<18} {name:<26} {api_version}{preview:<10} {flag}")

    if blocked:
        print()
        print(" ✗ 치환되지 않은 자리표시자가 있습니다.")
        print("   환경 변수를 설정하세요 (config/.env.example 참고).")
        if not args.dry_run:
            return 1

    if args.dry_run:
        print()
        print(" (연습 실행) 아무것도 배포하지 않았습니다.")
        return 0

    if not endpoint:
        print("\n ✗ AZURE_SEARCH_ENDPOINT 가 필요합니다.")
        return 1

    # ── 확인 프롬프트 ★ 자동으로 넘어가지 않는다
    print()
    print(" ⚠️  실제 Azure 리소스를 만듭니다.")
    print("     인덱서가 실행되면 Azure OpenAI 임베딩 비용이 발생합니다.")
    if args.env == "prd":
        print()
        print(" 🛑 운영 환경입니다.")
    print()
    answer = input(" 계속하려면 정확히 'yes' 를 입력하세요: ")
    if answer != "yes":
        print(" 취소했습니다.")
        return 1

    token = get_token()
    print()
    failures = 0
    for fname, path, name, body, api_version, _missing in plans:
        status, text = put_resource(endpoint, path, name, body, api_version, token)
        ok = 200 <= status < 300
        mark = "✓" if ok else "✗"
        print(f"   {mark} {path}/{name}  →  HTTP {status}")
        if not ok:
            failures += 1
            print(f"       {text}")

    print()
    print("-" * 70)
    if failures:
        print(f" 실패 {failures}건 — 위 오류를 확인하세요.")
        return failures

    print(" 배포 완료.")
    print()
    print(" 다음")
    print("   ① 데이터 업로드 (Blob) 또는 청크 직접 푸시")
    print("   ② 인덱서 실행    → ⚠️ 임베딩 과금 시작")
    print("   ③ 색인 확인      문서 수가 12,863 인지")
    print("   ④ 검증          python 테스트/eval/eval_retrieval.py")
    print("   ⑤ 플레이그라운드 개발/playground/시연_시나리오.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
