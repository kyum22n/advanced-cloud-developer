# -*- coding: utf-8 -*-
"""1차 정적 검증 — 외부 도구 설치 없이 항상 실행할 수 있는 검사.

왜 두 계층으로 나누는가
  ① 여기(1차): 파이썬 표준 라이브러리와 node --check 만 쓴다. 네트워크·설치가 필요 없다.
     → 어떤 환경에서도 «최소한의 방어선»이 항상 작동한다.
  ② run_static_all.ps1(2차): Checkstyle·SpotBugs·ESLint·tsc·Ruff·mypy 를 돌린다.
     → 도구가 설치된 환경에서 더 깊이 본다.

1차가 잡는 것은 «도구가 없어도 잡아야 하는 것»이다.
  - 계약 위반(엔드포인트 누락)
  - 비밀 하드코딩
  - 컨테이너 보안 규칙 위반(루트 실행·가변 태그·단일 스테이지)
  - 구문 오류
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTRACT = json.loads((ROOT / "공통" / "api-contract.json").read_text(encoding="utf-8"))

PROJECTS = {
    "backend/springboot": {"lang": "java", "kind": "backend"},
    "backend/nestjs": {"lang": "ts", "kind": "backend"},
    "backend/fastapi": {"lang": "py", "kind": "backend"},
    "frontend/html5": {"lang": "js", "kind": "frontend"},
    "frontend/vue": {"lang": "vue", "kind": "frontend"},
}

SKIP_DIRS = {"node_modules", ".venv", "dist", "target", "__pycache__", ".git", "reports"}

# 비밀이 코드에 박혀 있는지 본다. 환경 변수 참조는 제외한다.
# 세 번째 값이 True 면 «값이 실제로 자격 증명처럼 생겼는가»를 한 번 더 판정한다.
SECRET_PATTERNS = [
    (r"""(?i)(?:password|passwd|pwd)\s*[:=]\s*["']([^"']{4,})["']""",
     "비밀번호 하드코딩 의심", True),
    (r"""(?i)client_secret\s*[:=]\s*["']([^"']{8,})["']""",
     "클라이언트 시크릿 하드코딩", True),
    (r"(?i)AccountKey\s*=", "스토리지 계정 키 하드코딩", False),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "개인 키 포함", False),
    (r"0\.0\.0\.0/0", "전체 개방 네트워크 규칙", False),
]

# 검사에서 제외하는 «규칙 자체를 담은» 파일
#   verify_static.py  : 탐지 규칙을 담고 있다
#   api-contract.json : 금지 문자열 목록을 담고 있다
#   README.md         : 규칙을 설명한다
SECRET_SCAN_EXCLUDE = {"verify_static.py", "api-contract.json", "README.md"}

# 자격 증명이 «아닌» 것이 분명한 값 — 상수 이름·모드 이름·기본 계정명 등
BENIGN_LITERALS = {
    "password", "passwd", "pwd", "entra", "none", "null", "true", "false",
    "secret", "changeme", "example", "placeholder", "appuser", "postgres",
}


def is_test_path(path: Path) -> bool:
    """테스트 코드인지 본다.

    테스트 픽스처에는 «가짜 자격 증명»이 의도적으로 들어간다(U-A-10 이 그 예다).
    운영 코드의 하드코딩과 구분하지 않으면 규칙 자체를 끄게 되므로,
    자격 증명 계열 규칙만 테스트 경로에서 면제한다. AccountKey·개인 키·0.0.0.0/0 은 면제하지 않는다.
    """
    parts = {p.lower() for p in path.parts}
    if parts & {"test", "tests"}:
        return True
    name = path.name.lower()
    return name.startswith("test_") or name.endswith(("test.java", "test.js", "test.ts", "_test.py"))


def looks_like_credential(value: str) -> bool:
    """값이 실제 자격 증명처럼 생겼는지 본다.

    상수 선언(``PASSWORD = "password"``)이나 모드 이름을 비밀로 오인하지 않기 위한 최소 판정이다.
    자격 증명은 보통 8자 이상이며 숫자·기호를 섞거나 대소문자가 섞인다.
    """
    if value.lower() in BENIGN_LITERALS:
        return False
    if value.startswith(("$", "{", "<", "%")):
        return False
    if len(value) < 8:
        return False
    has_symbol_or_digit = any(c.isdigit() or not c.isalnum() for c in value)
    mixed_case = any(c.isupper() for c in value) and any(c.islower() for c in value)
    return has_symbol_or_digit or mixed_case


@dataclass
class Result:
    """검사 1건의 결과."""

    name: str
    status: str
    detail: str = ""


@dataclass
class Report:
    """전체 결과."""

    results: list[Result] = field(default_factory=list)

    def add(self, name: str, ok: bool, detail: str = "") -> None:
        """결과를 기록한다."""
        self.results.append(Result(name, "Pass" if ok else "Fail", detail))

    @property
    def failed(self) -> int:
        """실패 건수."""
        return sum(1 for r in self.results if r.status != "Pass")


def iter_source_files(base: Path, suffixes: tuple[str, ...]) -> list[Path]:
    """검사 대상 소스 파일을 모은다."""
    found: list[Path] = []
    for path in base.rglob("*"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.is_file() and path.suffix in suffixes:
            found.append(path)
    return found


def check_structure(report: Report) -> None:
    """프로젝트마다 있어야 할 파일이 있는지 본다."""
    required = {
        "backend/springboot": ["pom.xml", "Dockerfile", "checkstyle.xml", "README.md"],
        "backend/nestjs": ["package.json", "tsconfig.json", "Dockerfile", ".eslintrc.json", "README.md"],
        "backend/fastapi": ["pyproject.toml", "requirements.txt", "Dockerfile", "README.md"],
        "frontend/html5": ["public/index.html", "Dockerfile", ".eslintrc.json", "README.md"],
        "frontend/vue": ["package.json", "vite.config.js", "Dockerfile", ".eslintrc.json", "README.md"],
    }
    for project, files in required.items():
        missing = [f for f in files if not (ROOT / project / f).exists()]
        report.add(f"[구조] {project}", not missing, "누락: " + ", ".join(missing) if missing else "필수 파일 확인")


def check_contract(report: Report) -> None:
    """세 백엔드가 계약의 엔드포인트를 모두 구현했는지 본다."""
    expected = CONTRACT["endpoints"]
    for project in ("backend/springboot", "backend/nestjs", "backend/fastapi"):
        base = ROOT / project
        blob = "\n".join(
            p.read_text(encoding="utf-8", errors="ignore")
            for p in iter_source_files(base, (".java", ".ts", ".py"))
        )
        missing = []
        for ep in expected:
            path = ep["path"]
            # 프레임워크마다 표기가 다르므로 «경로 조각»으로 찾는다
            token = path.lstrip("/").replace("api/", "")
            if token not in blob:
                missing.append(f'{ep["method"]} {path}')
        report.add(
            f"[계약] {project} 엔드포인트 {len(expected)}종",
            not missing,
            "누락: " + ", ".join(missing) if missing else "모두 구현됨",
        )


def check_secrets(report: Report) -> None:
    """소스·설정에 비밀이 박혀 있는지 본다."""
    hits: list[str] = []
    for path in iter_source_files(ROOT, (".java", ".ts", ".js", ".py", ".vue", ".yml", ".yaml", ".json", ".conf")):
        if path.name in SECRET_SCAN_EXCLUDE:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for pattern, label, credential in SECRET_PATTERNS:
            for m in re.finditer(pattern, text):
                if credential:
                    if is_test_path(path):
                        continue
                    if not looks_like_credential(m.group(1) if m.groups() else ""):
                        continue
                line = text[: m.start()].count("\n") + 1
                hits.append(f"{path.relative_to(ROOT)}:{line} {label}")
    report.add("[보안] 비밀 하드코딩 없음", not hits, "; ".join(hits[:5]) if hits else "탐지 없음")


def check_dockerfiles(report: Report) -> None:
    """컨테이너 보안 규칙을 본다 — 비루트·멀티스테이지·불변 태그."""
    rules = CONTRACT["container"]
    for project in PROJECTS:
        dockerfile = ROOT / project / "Dockerfile"
        if not dockerfile.exists():
            report.add(f"[컨테이너] {project}", False, "Dockerfile 없음")
            continue
        text = dockerfile.read_text(encoding="utf-8")
        problems = []
        if rules["mustRunAsNonRoot"] and not re.search(r"^\s*USER\s+(?!root\b)\S+", text, re.M):
            problems.append("USER(비루트) 지시어 없음")
        if rules["mustBeMultiStage"] and len(re.findall(r"^\s*FROM\s", text, re.M)) < 2:
            # 정적 서빙처럼 빌드가 필요 없는 경우는 예외로 둔다
            if "nginx" not in text.lower():
                problems.append("멀티스테이지 아님")
        for tag in rules["forbiddenBaseTags"]:
            if re.search(rf"^\s*FROM\s+\S+:{tag}\b", text, re.M):
                problems.append(f"가변 태그 사용(:{tag})")
        report.add(f"[컨테이너] {project}", not problems, "; ".join(problems) if problems else "비루트·태그 고정 확인")


def check_syntax(report: Report) -> None:
    """구문 오류를 본다. 도구 설치 없이 가능한 범위까지."""
    py_files = iter_source_files(ROOT / "backend/fastapi", (".py",))
    bad_py = []
    for path in py_files:
        try:
            compile(path.read_text(encoding="utf-8"), str(path), "exec")
        except SyntaxError as exc:
            bad_py.append(f"{path.name}:{exc.lineno}")
    report.add("[구문] Python", not bad_py, "; ".join(bad_py) if bad_py else f"{len(py_files)}개 파일 정상")

    js_files = iter_source_files(ROOT / "frontend/html5", (".js",)) + iter_source_files(
        ROOT / "backend/nestjs" / "test", (".js",)
    )
    bad_js = []
    for path in js_files:
        proc = subprocess.run(  # noqa: S603
            ["node", "--check", str(path)], capture_output=True, text=True, check=False
        )
        if proc.returncode != 0:
            bad_js.append(path.name)
    report.add("[구문] JavaScript", not bad_js, "; ".join(bad_js) if bad_js else f"{len(js_files)}개 파일 정상")

    bad_json = []
    for path in iter_source_files(ROOT, (".json",)):
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            bad_json.append(f"{path.relative_to(ROOT)}:{exc.lineno}")
    report.add("[구문] JSON", not bad_json, "; ".join(bad_json) if bad_json else "정상")


def check_testids(report: Report) -> None:
    """두 프런트엔드가 같은 E2E 선택자를 쓰는지 본다."""
    required = {
        "create-form", "input-title", "input-amount", "btn-submit",
        "error-message", "empty-message", "item-tbody", "summary-tbody",
        "env-badge", "version-badge",
    }
    for project in ("frontend/html5", "frontend/vue"):
        blob = "\n".join(
            p.read_text(encoding="utf-8", errors="ignore")
            for p in iter_source_files(ROOT / project, (".html", ".js", ".vue"))
        )
        missing = sorted(t for t in required if f'data-testid="{t}"' not in blob)
        report.add(
            f"[E2E] {project} data-testid {len(required)}종",
            not missing,
            "누락: " + ", ".join(missing) if missing else "동일 선택자 사용",
        )


def check_env_usage(report: Report) -> None:
    """설정을 환경 변수로만 받는지 본다(NFR-07)."""
    required = CONTRACT["env"]["required"]
    for project in ("backend/springboot", "backend/nestjs", "backend/fastapi"):
        base = ROOT / project
        blob = "\n".join(
            p.read_text(encoding="utf-8", errors="ignore")
            for p in iter_source_files(base, (".java", ".ts", ".py", ".yml"))
        )
        missing = [name for name in required if name not in blob]
        report.add(
            f"[설정] {project} 환경 변수",
            not missing,
            "누락: " + ", ".join(missing) if missing else f"{len(required)}종 사용",
        )


def main() -> int:
    """전체 1차 검증을 수행한다."""
    report = Report()
    check_structure(report)
    check_contract(report)
    check_env_usage(report)
    check_testids(report)
    check_dockerfiles(report)
    check_secrets(report)
    check_syntax(report)

    width = max(len(r.name) for r in report.results)
    print("=" * (width + 46))
    print("개발/ 1차 정적 검증 — 도구 설치 없이 항상 실행되는 검사")
    print("=" * (width + 46))
    for r in report.results:
        mark = "PASS" if r.status == "Pass" else "FAIL"
        print(f"[{mark}] {r.name.ljust(width)}  {r.detail}")
    print("-" * (width + 46))
    total = len(report.results)
    print(f"합계 {total}건 · 통과 {total - report.failed} · 실패 {report.failed}")

    out_dir = Path(__file__).resolve().parent / "reports"
    out_dir.mkdir(exist_ok=True)
    payload = {
        "kind": "static-1st",
        "total": total,
        "pass": total - report.failed,
        "fail": report.failed,
        "results": [r.__dict__ for r in report.results],
    }
    (out_dir / "static_1st.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"리포트: {out_dir / 'static_1st.json'}")
    return 1 if report.failed else 0


if __name__ == "__main__":
    sys.exit(main())
