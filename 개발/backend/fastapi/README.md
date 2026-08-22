# Backend — Python (FastAPI)

| 항목 | 값 |
| --- | --- |
| 런타임 | Python 3.11 · FastAPI 0.115 · Uvicorn |
| DB 접근 | `psycopg` 3 (async) |
| 정적 검증 | Ruff(lint·import 정렬·보안 S 규칙) · mypy(strict) · Bandit |
| 계약 | [`개발/공통/openapi.yaml`](../../공통/openapi.yaml) |

## 실행

```powershell
python -m venv .venv ; .\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8080
```

## 정적 검증

```powershell
ruff check .
mypy app
bandit -q -r app
```

## 이 구현이 강조하는 것

- **`mypy strict`** — 타입 주석이 없는 함수를 허용하지 않습니다.
- **Ruff `S` 규칙(Bandit 계열)** — `assert` 남용·하드코딩 비밀 같은 보안 냄새를 잡습니다.
- **`_entra_token()`** — prd 에서 비밀번호 대신 토큰으로 접속합니다.
