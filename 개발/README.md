# 개발 — 하나의 계약, 다섯 가지 구현

> **이 폴더가 답하는 질문**: «같은 앱을 **다른 언어·다른 프레임워크**로 만들면 무엇이 같고 무엇이 달라지는가»
> **연결**: 설계 근거 [`설계/`](../설계/README.md) · 실행 절차 [`배포/`](../배포/README.md) · 실습 [`실습자료/3차시_…프롬프트.md`](../실습자료/3차시_나만의업무앱만들기_실습_프롬프트.md)

---

## 1. 왜 다섯 가지를 만드는가

한 가지 스택만 다루면 «그 프레임워크 쓰는 법»을 배우고 끝납니다.
**같은 계약을 여러 스택으로 구현해 보면**, 프레임워크가 대신해 주는 것과 **어느 스택에서도 내가 책임져야 하는 것**이 갈립니다.

| 어느 스택에서도 동일한 것 (= 설계) | 스택마다 다른 것 (= 구현) |
| --- | --- |
| API 계약 · 상태 코드 | 라우팅 표기법 |
| 환경 변수로만 설정을 받는 규칙 | 설정 바인딩 방식 |
| `/healthz` 는 의존성을 보지 않는다 | 프로브 구현 코드 |
| 비밀을 코드에 두지 않는다 | 커넥션 풀 API |
| 순수 로직은 단위 테스트로 고정한다 | 테스트 러너 |
| 컨테이너는 비루트·멀티스테이지 | 베이스 이미지 |

---

## 2. 폴더 구조

```
개발/
├── 공통/
│   ├── openapi.yaml            ← API 계약(설계/공통/03 을 기계 판독용으로 옮긴 것)
│   └── api-contract.json       ← 정적 검증기가 읽는 계약 요약
├── backend/
│   ├── springboot/             Java 17 · Spring Boot 3.3 · Maven
│   ├── nestjs/                 Node 20 · NestJS 10 · TypeScript 5(strict)
│   └── fastapi/                Python 3.11 · FastAPI · psycopg3(async)
├── frontend/
│   ├── html5/                  바닐라 JS · 빌드 없음 · nginx 서빙
│   └── vue/                    Vue 3 · Vite · nginx 서빙
└── 정적검증/
    ├── verify_static.py        1차 — 도구 없이 항상 실행
    ├── run_static_all.ps1      2차 — 언어별 도구 전체
    └── reports/                실행 리포트
```

---

## 3. 하나의 계약 — 엔드포인트 6종

| # | 메서드 | 경로 | 용도 | 쓰기 | prd 테스트 |
| --- | --- | --- | --- | :---: | :---: |
| 1 | GET | `/healthz` | 생존 프로브 — **의존성을 보지 않는다** | – | ✅ |
| 2 | GET | `/readyz` | 준비 프로브 — **DB 연결을 실제로 확인** | – | ✅ |
| 3 | GET | `/version` | 배포 버전·환경·**인증 방식** | – | ✅ |
| 4 | GET | `/api/items` | 항목 목록(최신순 200건) | – | ✅ |
| 5 | POST | `/api/items` | 항목 등록 | ✅ | **⏭ 건너뜀** |
| 6 | GET | `/api/summary` | ISO 주차별 집계 | – | ✅ |

> 🔎 **`/healthz` 에서 DB 를 확인하면 안 되는 이유** — DB 가 잠시 끊겼을 때 **파드가 재시작**되어 상황이 악화됩니다. 그건 `/readyz` 의 역할입니다. 세 구현 모두 이 규칙을 지킵니다.

---

## 4. 백엔드 3종 비교

| 관점 | **Spring Boot** | **NestJS** | **FastAPI** |
| --- | --- | --- | --- |
| 언어·런타임 | Java 17 | TypeScript 5 · Node 20 | Python 3.11 |
| DB 접근 | `JdbcTemplate` | `pg` Pool | `psycopg` 3 (async) |
| 순수 로직 분리 | `domain/SummaryCalculator` | `common/summary.ts` | `app/summary.py` |
| 인증 방식 선택 | `config/AuthMode` | `common/authmode.ts` | `app/authmode.py` |
| 타입 안정성 | 컴파일러 | `tsc --strict` | `mypy --strict` |
| 정적 분석 | Checkstyle · SpotBugs | ESLint(`no-explicit-any: error`) | Ruff(보안 `S` 포함) · Bandit |
| 단위 테스트 | JUnit 5 | `node:test` | pytest |
| 이미지 크기 경향 | 큼(JRE) | 중간 | 작음 |
| 기동 속도 | 느림 | 빠름 | 빠름 |

### 4-1. 무엇을 고를 것인가

| 상황 | 권장 | 이유 |
| --- | --- | --- |
| 사내 표준이 Java · 기존 자산이 많음 | **Spring Boot** | 인력·라이브러리·운영 노하우가 이미 있음 |
| 프런트엔드와 **같은 언어**로 통일하고 싶음 | **NestJS** | 타입·도구·인력을 공유 |
| 데이터 처리·AI 연동이 중심 | **FastAPI** | 파이썬 생태계 · async 성능 |
| **기동 속도·이미지 크기**가 중요(서버리스·스케일아웃) | FastAPI · NestJS | JVM 기동 부담 없음 |

> ⚠️ **«무엇이 더 낫다»는 질문은 대개 답이 없습니다.** 팀이 유지보수할 수 있는 스택이 가장 좋은 스택입니다. 이 폴더는 **세 가지를 나란히 두고 직접 비교**해 볼 수 있게 하는 것이 목적입니다.

---

## 5. 프런트엔드 2종 비교

| 관점 | **HTML5(바닐라)** | **Vue 3** |
| --- | --- | --- |
| 빌드 | **없음** | Vite |
| 화면 갱신 | DOM 을 직접 만들고 지운다 | **상태를 바꾸면 자동 반영** |
| 재사용 단위 | 함수 | **컴포넌트** |
| XSS 방어 | `textContent` 를 직접 지켜야 함 | **기본 이스케이프**(`v-html` 은 ESLint 로 금지) |
| 배포 이미지 | nginx + 정적 파일 | 멀티스테이지(빌드 → nginx) |
| **E2E 선택자** | **`data-testid` 동일** | **`data-testid` 동일** |

> 🔑 **두 구현의 `data-testid` 가 같다는 점이 핵심입니다.** 프런트엔드를 교체해도 **E2E 테스트는 그대로** 씁니다. 이것이 «화면 문구가 아니라 테스트 ID 로 찾는» 이유입니다.

---

## 6. 세 환경에 어떻게 올라가는가

| 환경 | 백엔드 이미지 | 프런트엔드 | DB 인증 | 참고 |
| --- | --- | --- | --- | --- |
| **dev** | 셋 중 택1 · `myapp:dev-<sha>` | 택1 · nginx | `password`(환경 변수) | [dev 설계](../설계/dev/01_아키텍처설계서_dev.md) |
| **stg** | ACR `myapp:stg-<sha>` | ACR | `password`(K8s Secret) | [stg 설계](../설계/stg/01_아키텍처설계서_stg.md) |
| **prd** | ACR `myapp:prd-<sha>`(불변) | ACR | **`entra`(워크로드 ID 토큰)** | [prd 설계](../설계/prd/01_아키텍처설계서_prd.md) |

**세 구현 모두 인증 방식을 «환경이 스스로» 고릅니다** — 이미지는 하나입니다(NFR-07).

| `DB_PASSWORD` | 워크로드 ID 환경 변수 | 선택되는 모드 |
| :---: | :---: | --- |
| 있음 | 없음 | `password` |
| 있음 | 있음 | `password` |
| **없음** | **있음** | **`entra`** |

> 📐 근거: [설계/공통/07 아이덴티티·시크릿 설계서 §5](../설계/공통/07_아이덴티티·시크릿_설계서.md)

---

## 7. 정적 검증 — 배포 전에 «싸게» 잡는다

```powershell
cd 개발\정적검증
python .\verify_static.py                       # 1차 — 도구 없이 항상 실행
pwsh -File .\run_static_all.ps1 -SkipInstall    # 2차 — 언어별 도구 전체
```

| 계층 | 필요한 것 | 잡는 것 |
| --- | --- | --- |
| **1차** | Python · Node | 계약 위반 · 비밀 하드코딩 · 컨테이너 보안 · 구문 오류 · **두 프런트엔드의 `data-testid` 일치** |
| **2차** | 언어별 도구 | 타입 · 버그 패턴 · 코딩 규칙 · 단위 테스트 |

자세한 내용은 [`정적검증/README.md`](정적검증/README.md) 를 보세요.

---

## 8. 어떻게 시작하나

```powershell
# ① 계약을 먼저 읽는다
code 개발\공통\openapi.yaml

# ② 하나를 골라 띄운다 (예: FastAPI)
cd 개발\backend\fastapi
python -m venv .venv ; .\.venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
uvicorn app.main:app --reload --port 8080

# ③ 프런트엔드를 붙인다 (예: Vue)
cd ..\..\frontend\vue
npm install ; npm run dev        # http://localhost:5173

# ④ 정적 검증을 돌린다
cd ..\..\정적검증 ; python .\verify_static.py
```

> 💡 **DB 가 없어도 `/healthz` 와 화면은 뜹니다.** `/readyz` 만 503 을 돌려줍니다 — 이 동작이 «생존과 준비를 나눈» 설계의 결과입니다.
> DB 가 필요하면 `배포\dev\20_config.ps1` 이 만드는 in-cluster PostgreSQL 을 쓰거나, 로컬 도커로 `postgres:16-alpine` 을 띄우세요.

---

## 9. 내 주제로 바꾸기

```text
개발/ 폴더의 구현 중 하나를 골라 내 앱 주제에 맞게 바꿔줘.

[선택]
- 백엔드: (springboot | nestjs | fastapi 중 하나)
- 프런트엔드: (html5 | vue 중 하나)
- 내 주제: (예: 회의록 액션아이템 관리)

[반드시 지킬 것]
- 개발/공통/openapi.yaml 을 먼저 고치고, 그 다음에 구현을 고칠 것 — 계약이 먼저다.
- /healthz 는 의존성을 확인하지 않는다는 규칙을 유지할 것.
- 설정은 환경 변수로만 받을 것. 비밀값을 코드·Git·이미지에 두지 말 것.
- data-testid 는 프런트엔드 두 구현에서 동일하게 유지할 것.
- 순수 로직(집계·검증)은 반드시 별도 모듈로 분리하고 단위 테스트를 함께 고칠 것.

[검증]
- 개발/정적검증/verify_static.py 가 전부 Pass 할 때까지 고칠 것.
- 그다음 run_static_all.ps1 로 언어별 도구 검증까지 통과시킬 것.
- 결과를 O/X 표로 보고하고, 계약을 바꿨다면 무엇을 왜 바꿨는지 3줄로 요약할 것.
```
