# 공통 샘플 앱 (배포 파이프라인 검증용)

> 3차시 실습에서 만든 `실습산출물\3차시\myapp` 이 아직 없을 때, **dev·stg·prd 배포 스크립트가 실제로 동작하는지 확인**하기 위한 최소 앱입니다.
> 실습으로 만든 앱이 준비되면 스크립트가 자동으로 그쪽을 우선 사용합니다(`Resolve-AppPath`).

## 구성

| 경로 | 역할 |
| --- | --- |
| `src/lib/summary.js` | **순수 로직** — 주차 집계·중복 제거·PII 마스킹 (단위 테스트 대상) |
| `src/db.js` | PostgreSQL 연결 (환경 변수만 사용 — 비밀값 하드코딩 없음) |
| `src/server.js` | HTTP 서버 · `/healthz` `/readyz` `/version` `/api/items` `/api/summary` |
| `public/index.html` | 목록·입력 화면 (E2E 대상, `data-testid` 부여) |
| `test/unit/` | 단위 테스트 6건 (`node --test`) |
| `test/integration/` | 통합 테스트 6건 (실제 API+DB, `BASE_URL` 주입) |
| `test/e2e/` | E2E 테스트 4건 (Playwright, 캡처 저장) |
| `Dockerfile` | 멀티스테이지 · **비루트 실행** · HEALTHCHECK 포함 |

## 로컬에서 바로 실행

```powershell
cd 배포\common\app
npm install
$env:DB_HOST="localhost"; $env:DB_NAME="appdb"; $env:DB_USER="appuser"; $env:DB_PASSWORD="<직접 입력>"
npm start                       # http://localhost:8080
npm run test:unit               # 단위 테스트만은 DB 없이 실행 가능
```

## 환경 변수

| 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `PORT` | 8080 | 수신 포트 |
| `APP_ENV` | dev | 화면·응답에 표시되는 환경 이름 |
| `APP_VERSION` | 0.0.0 | 배포된 이미지 태그(스크립트가 주입) |
| `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USER` / `DB_PASSWORD` | – | DB 연결 정보 |
| `DB_SSL` | false | `true` 면 TLS 연결(Azure PaaS DB에서 필요) |
