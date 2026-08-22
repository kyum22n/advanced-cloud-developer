# 3차시 — 웹 테트리스(APP-B) 개발 · dev(k3d) → stg(AKS+ArgoCD) 배포 결과산출물

> 대상 앱: `설계/공통/01_기능명세서.md` APP-B 웹 테트리스 (기존 APP-A 나만의 업무 앱을 대체)
> 소스: [`개발/frontend/tetris/`](../../개발/frontend/tetris/) · 배포 단위: [`실습산출물/3차시/myapp/`](myapp/)
> Git 저장소: https://github.com/kyum22n/advanced-cloud-developer (master)

---

## 1. 개발 — 웹 테트리스(APP-B)

설계/공통/02 §3 클래스 설계(GameEngine·Board·Piece·SrsKick·ScoreRule)를 그대로 구현했다.

| 항목 | 내용 |
| --- | --- |
| 런타임 | 바닐라 JS + Canvas, 빌드 도구 없음(NFR-B-01) |
| 엔진 분리 | `public/js/engine.js`·`srsKick.js`·`scoreRule.js` — DOM 참조 없음(NFR-B-02) |
| 렌더·입력 | `public/js/main.js` — Canvas 렌더 루프 · 키보드 입력 |
| 배포 형태 | `nginxinc/nginx-unprivileged:1.27-alpine` 정적 서빙, 상태·DB 없음(NFR-B-04) |
| 구현 기능 | 이동·SRS 회전+월킥·소프트/하드드롭·라인클리어·점수/레벨·홀드·일시정지·게임오버(FR-B-01~12) |

### 1-1. 개발 중 발견·수정한 실제 버그

| # | 증상 | 원인 | 수정 |
| --- | --- | --- | --- |
| 1 | `CreateContainerConfigError` | `runAsNonRoot: true`인데 `USER appuser`(이름)라 커널이 UID를 정적으로 검증 못함 | `USER 10001`(FastAPI) / `USER 101`(nginx) 숫자 UID로 변경 |
| 2 | nginx `mkdir /var/cache/nginx/client_temp: Permission denied`로 CrashLoopBackOff | 공식 `nginx:alpine`의 `/var/cache/nginx`가 root 소유 | `nginxinc/nginx-unprivileged` 이미지로 전환 |
| 3 | Playwright `Project(s) "chromium" not found` | `playwright.config.js`에 `projects` 배열 자체가 없었음(원본 템플릿 버그) | `projects: [{name:"chromium", ...}]` 추가 |
| 4 | PowerShell `Invoke-WebRequest`가 `/version` 응답을 바이너리로 오판 | `add_header Content-Type`이 기존 헤더에 추가되어 **Content-Type 헤더 중복** | `default_type`으로 교체 |
| 5 | `kubectl apply`로 Argo CD 설치 시 `applicationsets` CRD 적용 실패 | client-side apply의 `last-applied-configuration` 주석이 262144바이트 한도 초과 | `kubectl apply --server-side --force-conflicts`로 전환 |

---

## 2. dev 환경 (로컬 k3d, Docker Desktop)

| 단계 | 결과 |
| --- | --- |
| 전제조건(10) | 7/7 pass |
| 구성(20) — k3d 클러스터·ConfigMap·Secret·PostgreSQL | 완료 |
| 빌드(30) — `myapp:dev-local` | 완료 |
| 배포(40) — `http://localhost:8080` | 완료 |
| 단위(50) — U-B-01~10 | **10/10 pass** |
| 통합(60) | 설계상 해당 없음(APP-B는 통합 TC 대상 아님, 명시적으로 skip) |
| E2E(70) — E-B-01~04, Playwright | **4/4 pass**, 캡처 4장 |
| 검증(80) | **7/7 pass** |

### 2-1. Playwright MCP 자동 플레이

브라우저 자동화(실제 `keydown` 이벤트 발생)로 게임을 플레이해 **1000점**에 정확히 도달했다.

- 조각 34개, 게임오버 0회, 소요 15ms(엔진 연산 기준), 최종 레벨 2
- 전략: 보드 스냅샷(`grid`)을 읽어 각 조각의 회전·x좌표 후보를 시뮬레이션한 뒤 (줄 클리어 최대화·구멍/높이/요철 최소화) 점수가 가장 높은 수를 실제 키 입력으로 실행
- 이를 위해 숨김 `[data-testid="debug-state"]`에 스택 격자(`grid`)를 노출하는 코드를 추가(게임 로직 자체는 변경 없음)

---

## 3. stg 환경 (Azure AKS + Argo CD GitOps)

### 3-1. 준비

| 항목 | 값 |
| --- | --- |
| Git 원격 저장소 | https://github.com/kyum22n/advanced-cloud-developer (신규 생성, public) |
| Azure 구독 | Azure in Open (테넌트: 신한대학교) |
| 리소스 그룹 | `rg-myapp-stg` (koreacentral) |
| AKS | `aks-myapp-stg` — 노드 2 · `Standard_D2s_v5` · OIDC 발급자 · Workload Identity 활성화 |
| ACR | `acrmyappstg` (AKS에 attach, kubelet 관리 ID로 pull — imagePullSecret 불필요) |
| GitOps | Argo CD, `syncPolicy.automated`(prune+selfHeal) |
| 배포 이미지 | `acrmyappstg.azurecr.io/myapp:stg-afd30ab` (`az acr build`로 클라우드 빌드) |
| 접속 주소 | `http://20.249.107.0` (LoadBalancer) |

### 3-2. 테스트 결과 — 실제 AKS 배포본 대상

| 단계 | 결과 |
| --- | --- |
| 전제조건(10) | 12/12 pass |
| 구성(20) — RG·ACR·AKS·Argo CD·Project/Application·Secret | 완료 |
| 빌드(30) — `az acr build` | 완료 |
| 배포(40) — Git 커밋·푸시 → Argo CD 자동 동기화 → LoadBalancer IP 확보 | 완료 |
| 단위(50) | **10/10 pass** |
| 통합(60) | 설계상 해당 없음(skip) |
| E2E(70) | **4/4 pass**, 캡처 4장(`stg_B01~B04`) |
| 검증(80) | **12/12 pass** |

검증(80) 세부 — 12개 전부 Pass:

```
Argo CD sync = Synced · health = Healthy
readyReplicas >= 2
배포 이미지 = 최신 빌드 태그(stg-afd30ab)
엔드포인트 /healthz · /readyz · /version
AKS OIDC 발급자 사용(워크로드 ID 전제)
AKS 워크로드 ID 애드온 사용
kubelet 관리 ID로 ACR pull(imagePullSecret 없음)
imagePullSecret 미사용
selfHeal: 레플리카를 2→1로 수동 변경 → Argo CD가 자동으로 2로 복구
```

**selfHeal 실증**이 이번 stg 검증의 핵심이다 — 클러스터를 수동으로 건드려도(드리프트) Argo CD가 Git의 상태로 즉시 되돌린다는 GitOps의 원칙을 실제로 확인했다.

---

## 4. 비용 · 정리

- stg의 AKS(노드 2)·ACR·LoadBalancer는 **시간당 과금**된다.
- 이 문서 작성 직후 `배포\stg\90_cleanup.ps1`로 정리한다(리소스 그룹 삭제 → RG에 속한 AKS·ACR·LoadBalancer 공인 IP 모두 함께 삭제됨).
- dev(k3d)는 로컬 Docker 자원만 사용하므로 비용 없음 — 필요 시 `배포\dev\90_cleanup.ps1`로 별도 정리.
- Git 저장소(GitHub, public)와 이 문서·테스트 리포트(JSON)·E2E 캡처(PNG)는 정리 이후에도 남아 재현·복기가 가능하다.

## 5. 산출물 경로

| 종류 | 경로 |
| --- | --- |
| 소스 | [`개발/frontend/tetris/`](../../개발/frontend/tetris/) |
| 배포 단위 | [`실습산출물/3차시/myapp/`](myapp/) |
| dev 테스트 리포트 | `배포/dev/reports/dev_*.json` |
| stg 테스트 리포트 | `배포/stg/reports/stg_*.json` |
| E2E 캡처 | `실습산출물/3차시/myapp/test/e2e/캡처/*.png` (실행할 때마다 재생성) |
| Git 커밋 이력 | `afd30ab` 초기 커밋 → `9cd2da6` stg 이미지 태그 배포 → `b3c6410` Argo CD 설치 수정 |
