# 3환경 배포 가이드 — dev · stg · prd (따라하기)

> 대상: 3차시 「나만의 업무 앱 만들기」에서 만든 앱(또는 공통 샘플 앱)
> 목표: **로컬에서 만든 앱을 검증 환경을 거쳐 운영 환경까지 올리는 전 과정**을, 명령을 그대로 따라 하며 완성합니다.
> 전제: 1차시 Part A~C(도구·MCP) 및 Part D(Azure CLI) 완료 · `az login` 상태

---

## 0. 시작 전에 — 이 가이드의 구조

### 0-1. 세 환경은 «목적»이 다릅니다

| 구분 | **dev** | **stg** | **prd** |
| --- | --- | --- | --- |
| **한 문장 목적** | 빠르게 만들고 **빠르게 버린다** | **배포 방식 자체**를 검증한다 | **가용성·보안·복구**가 기본값이다 |
| 실행 위치 | 내 PC (Docker Desktop) | Azure | Azure |
| 오케스트레이터 | **k3d** (경량 k8s) | **AKS** (Free 계층) | **AKS** (Standard · 영역 분산) |
| 이미지 빌드 | `docker build` → `k3d image import` | **`az acr build`** (클라우드 빌드) | `az acr build` + **불변 태그** |
| 배포 방식 | `kubectl apply` (직접) | **Argo CD 자동 동기화**(selfHeal) | **Argo CD 수동 Sync**(사람 승인) |
| 데이터베이스 | in-cluster PostgreSQL | in-cluster PostgreSQL(StatefulSet) | **PaaS PostgreSQL 유연한 서버**(HA·백업) |
| 비밀 관리 | `kubectl create secret` | `kubectl create secret` | **Key Vault + CSI + 워크로드 ID** |
| 외부 노출 | NodePort + 포트 매핑 | LoadBalancer | **관리형 NGINX Ingress + 내부 LB** |
| 쓰기 테스트 | 허용 | 허용 | **금지(읽기 전용 스모크)** |
| 비용 | 0 | 낮음(시간당) | 높음(시간당) |
| 정리 | `k3d cluster delete` | `az group delete` | `az group delete` (실습 시에만) |

> 💡 **왜 이렇게 나누는가** — dev 는 «속도», stg 는 «배포 방식의 정확성», prd 는 «장애가 나도 살아남는 것»을 각각 검증합니다. 한 환경에서 세 가지를 다 하려 하면 어느 것도 제대로 되지 않습니다.

### 0-2. 세 환경 모두 «같은 9단계»를 따릅니다

```
 10 전제조건 → 20 구성 → 30 빌드 → 40 배포 → 50 단위 → 60 통합 → 70 E2E → 80 검증 → 90 정리
 ─────────   ────    ────    ────   ───────────────────────   ────    ────
 도구·권한   인프라   이미지   반영   테스트 3단계(피라미드)      합격판정  뒷정리
```

| 단계 | 파일 | 무엇을 하나 | 실패하면 |
| --- | --- | --- | --- |
| **10 전제조건** | `10_prereq.ps1` | 도구·로그인·권한·이름 규칙 점검 | 뒤 단계가 중간에 멈춥니다 → 먼저 해결 |
| **20 구성** | `20_config.ps1` | 클러스터·네트워크·DB·비밀·플랫폼 준비 | 배포할 «곳»이 없습니다 |
| **30 빌드** | `30_build.ps1` | 컨테이너 이미지 생성 + 태그 부여 | 배포할 «것»이 없습니다 |
| **40 배포** | `40_deploy.ps1` | 매니페스트 반영 + 롤아웃 완료 대기 | 이전 버전이 그대로 남습니다 |
| **50 단위** | `50_test_unit.ps1` | 외부 의존 없이 **순수 로직** 검증 | 코드 자체가 잘못됨 |
| **60 통합** | `60_test_integration.ps1` | **API + DB 연동** 검증 | 연결·설정이 잘못됨 |
| **70 E2E** | `70_test_e2e.ps1` | **브라우저로 사용자 경로** 검증 + 캡처 | 화면·흐름이 잘못됨 |
| **80 검증** | `80_verify.ps1` | 리소스 상태·버전 일치·환경별 기준 | 「됐다고 생각했는데 안 된 것」 발견 |
| **90 정리** | `90_cleanup.ps1` | 리소스 제거 (되돌릴 수 없음) | 비용이 계속 발생 |

> 🧪 **테스트 3단계를 왜 나누나** — **단위**는 «내 계산이 맞나»(빠름·DB 불필요), **통합**은 «연결이 맞나»(실제 DB), **E2E**는 «사용자가 실제로 쓸 수 있나»(브라우저)를 봅니다. 아래로 갈수록 느리고 비싸므로 **위에서 먼저 걸러냅니다.**

### 0-3. 폴더 구조

```
배포/
├── common/
│   ├── lib.ps1              # 공통 함수 (로깅·검증·리포트·확인 프롬프트)
│   └── app/                 # 공통 샘플 앱 (myapp 이 없을 때 자동 사용)
├── dev/    10~90 스크립트 + config/k8s/ + README.md
├── stg/    10~90 스크립트 + config/{k8s(base·overlays), argocd}/ + README.md
├── prd/    10~90 + rollback.ps1 + config/{k8s, argocd, infra}/ + README.md
└── 가이드/  이 문서
```

> 📌 **앱 소스는 자동으로 결정됩니다** — `실습산출물\3차시\myapp\Dockerfile` 이 있으면 그것을, 없으면 `배포\common\app` 을 사용합니다. 직접 지정하려면 모든 스크립트에 `-AppPath <경로>` 를 붙이세요.

---

# 1부. dev — 로컬 k3d 개발 환경

> ⏱️ 예상 시간 **15~20분** · 💰 비용 **0원**

## 1-1. 사전 확인

Docker Desktop 이 **실행 중**이어야 합니다(트레이 아이콘이 초록색).

```powershell
cd C:\dev\workspace-igm\advanced-cloud-developer\배포\dev
docker version                      # 서버(Server) 섹션이 나와야 정상
```

k3d 가 없다면 설치합니다.

```powershell
winget install --id k3d.k3d -e      # 또는  choco install k3d
```

## 1-2. STEP 1 — 전제조건 점검

```powershell
pwsh -File .\10_prereq.ps1
```

**기대 결과** — 표의 모든 항목이 `Pass`:

```
  테스트                                         결과
  ------------------------------------------------------
  명령: docker                                   Pass
  명령: kubectl                                  Pass
  명령: k3d                                      Pass
  명령: node                                     Pass
  Docker 엔진 기동                               Pass
  호스트 포트 8080 가용                          Pass
  앱 Dockerfile 존재                             Pass
```

> ⚠️ **포트 8080 이 사용 중**이라고 나오면 `config\env.dev.json` 의 `cluster.hostPort` 를 8081 등으로 바꾸고, 같은 파일의 `test.baseUrl` 도 함께 바꾸세요.

## 1-3. STEP 2 — 환경 구성 (클러스터·설정·DB)

```powershell
# (선택) DB 비밀번호를 환경 변수로 — 지정하지 않으면 개발용 기본값이 쓰입니다
$env:DEV_DB_PASSWORD = "dev-" + [guid]::NewGuid().ToString("N").Substring(0,12)

pwsh -File .\20_config.ps1
```

이 스크립트가 하는 일:

1. **k3d 클러스터 생성** — 호스트 `8080` → NodePort `30080` 매핑
2. `kubectl` 컨텍스트를 `k3d-myapp-dev` 로 전환
3. 네임스페이스 `myapp-dev` 생성
4. **ConfigMap**(비밀 아닌 설정) · **Secret**(DB 비밀번호) 생성
5. **in-cluster PostgreSQL** 배포 후 준비 완료까지 대기

**확인**

```powershell
kubectl get nodes
kubectl get pods -n myapp-dev          # postgres 파드가 Running/1-1
```

## 1-4. STEP 3 — 빌드

```powershell
pwsh -File .\30_build.ps1
```

- `docker build` 로 이미지를 만들고 **git SHA 를 태그에 포함**합니다 (`dev-<sha>`)
- **`k3d image import`** 로 클러스터에 직접 반입합니다 — 레지스트리가 필요 없습니다
- 태그를 `reports\last-build.json` 에 기록해 다음 단계가 그대로 씁니다

## 1-5. STEP 4 — 배포

```powershell
pwsh -File .\40_deploy.ps1
```

매니페스트 적용 → 이미지 태그 지정 → `APP_VERSION` 주입 → **롤아웃 완료 대기** → `/healthz` 응답 확인까지 자동으로 진행합니다.

**브라우저로 확인**: <http://localhost:8080>

```powershell
curl http://localhost:8080/healthz     # {"status":"ok","env":"dev"}
curl http://localhost:8080/version     # 방금 빌드한 태그가 보여야 함
```

## 1-6. STEP 5~7 — 테스트 3단계

```powershell
pwsh -File .\50_test_unit.ps1          # 단위 — DB 없이 순수 로직 6건
pwsh -File .\60_test_integration.ps1   # 통합 — 실제 API+DB 6건
pwsh -File .\70_test_e2e.ps1           # E2E  — 브라우저 4건 + 캡처
```

E2E 캡처는 `<앱>\test\e2e\캡처\dev_01~04_*.png` 에 저장됩니다.

> 💡 **최초 실행 시** Playwright 브라우저(약 130MB)를 내려받으므로 1~2분 걸립니다.

## 1-7. STEP 8 — 배포 검증

```powershell
pwsh -File .\80_verify.ps1
```

| 검증 항목 | 통과 기준 |
| --- | --- |
| Deployment readyReplicas | ≥ 1 |
| 파드 Running | ≥ 1 |
| 컨테이너 재시작 | 3회 미만 (크래시 루프 아님) |
| `/healthz` `/readyz` `/version` | 모두 200 |
| **배포 버전 = 직전 빌드 태그** | 일치 |

## 1-8. 한 번에 실행하기

```powershell
pwsh -File .\run_all.ps1               # 10 → 80 전체
pwsh -File .\run_all.ps1 -SkipTests    # 테스트 제외
```

## 1-9. STEP 9 — 정리

```powershell
pwsh -File .\90_cleanup.ps1            # 확인 프롬프트에 'yes' 입력
```

## 1-10. dev 문제 해결

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| `k3d cluster create` 실패 | Docker 엔진 미기동 | Docker Desktop 실행 후 재시도 |
| 파드가 `ImagePullBackOff` | 이미지를 클러스터에 반입하지 않음 | `.\30_build.ps1` 재실행 |
| `/readyz` 가 503 | PostgreSQL 준비 전 | `kubectl get pods -n myapp-dev` 로 postgres Running 확인 |
| 브라우저 접속 불가 | 포트 매핑 충돌 | `env.dev.json` 의 `hostPort` 변경 후 클러스터 재생성 |
| E2E 가 타임아웃 | 앱 미배포 | `.\40_deploy.ps1` 먼저 실행 |

---

# 2부. stg — AKS + Argo CD GitOps 검증 환경

> ⏱️ 예상 시간 **35~45분**(AKS 생성 5~10분 포함) · 💰 비용 **시간당 과금 — 실습 후 반드시 정리**

## 2-1. 사전 준비 (필수 2가지)

`배포\stg\config\env.stg.json` 을 열어 **두 값을 바꿉니다.**

```jsonc
{
  "azure": {
    "acrName": "acrmyappstg{본인이니셜}"          // ← 전역 고유 · 소문자+숫자 5~50자
  },
  "argocd": {
    "repoUrl": "https://github.com/{계정}/{저장소}.git"   // ← Argo CD 가 감시할 Git 저장소
  }
}
```

> ⚠️ **`repoUrl` 이 왜 필수인가** — GitOps 는 **Git 이 «무엇을 배포할지»의 단일 진실**입니다. 저장소가 없으면 Argo CD 가 볼 대상이 없고, 스크립트는 `kubectl` 직접 적용으로 폴백하지만 **GitOps 를 검증할 수 없습니다.**

프로젝트를 Git 저장소로 만들고 원격에 연결합니다(이미 되어 있으면 건너뜁니다).

```powershell
cd C:\dev\workspace-igm\advanced-cloud-developer
git init
git add . ; git commit -m "chore: 3차시 배포 파이프라인 초기 커밋"
git remote add origin https://github.com/{계정}/{저장소}.git
git branch -M main ; git push -u origin main
```

## 2-2. STEP 1 — 전제조건 점검

```powershell
cd 배포\stg
az login                              # 이미 로그인되어 있으면 생략
az account show -o table              # 대상 구독이 맞는지 확인
pwsh -File .\10_prereq.ps1
```

점검 항목: `az`·`kubectl`·`git`·`node` / Azure 로그인 / 리전 가용성 / **리소스 공급자 등록** / ACR 이름 형식 / **repoUrl 지정** / Git 저장소 여부.

> 공급자가 미등록이면: `az provider register --namespace Microsoft.ContainerService --wait`

## 2-3. STEP 2 — 구성 (AKS · ACR · Argo CD)

```powershell
$env:STG_DB_PASSWORD = "Stg-" + [guid]::NewGuid().ToString("N").Substring(0,16) + "!"
pwsh -File .\20_config.ps1
```

**이 스크립트가 순서대로 하는 일** (의존 관계 순):

1. 리소스 그룹 `rg-myapp-stg`
2. **ACR** 생성 (Basic)
3. **AKS** 생성 — Azure CNI **Overlay** · 워크로드 ID · OIDC 발급자 · **`--attach-acr`** (ACR 인증을 자동 구성)
4. `az aks get-credentials` 로 kubeconfig 병합
5. **Argo CD 설치** (`argocd` 네임스페이스) 후 준비 완료까지 대기
6. **AppProject · Application 등록** — `repoUrl` 을 치환해 적용
7. 앱 네임스페이스와 **Secret 생성** (값은 화면에 출력하지 않음)

> ⏳ AKS 생성에 5~10분이 걸립니다. 진행 로그가 멈춘 것처럼 보여도 기다리세요.

**Argo CD UI 접속**

```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d   # 초기 비밀번호
kubectl port-forward svc/argocd-server -n argocd 8090:443
# 브라우저: https://localhost:8090   (ID: admin · 인증서 경고는 «고급 → 계속»)
```

## 2-4. STEP 3 — 빌드 (ACR 클라우드 빌드)

```powershell
pwsh -File .\30_build.ps1
```

**`az acr build`** 는 소스를 ACR 로 보내 **클라우드에서 빌드·푸시**합니다 — 로컬 Docker 엔진이 필요 없습니다. 태그는 `stg-<git-sha>` 형식입니다.

## 2-5. STEP 4 — GitOps 배포 (핵심 단계)

```powershell
pwsh -File .\40_deploy.ps1
```

**이 단계에서 실제로 일어나는 일:**

```
 ①  overlays/stg/kustomization.yaml 의  newTag 를  stg-<sha> 로 갱신
        ↓
 ②  git add / commit / push        ← 이 커밋이 곧 «배포 지시»
        ↓
 ③  Argo CD 가 저장소 변경을 감지 (또는 hard refresh 요청)
        ↓
 ④  선언 상태(Git) 와 실제 상태(클러스터) 를 비교해 차이만 적용
        ↓
 ⑤  Synced + Healthy 가 될 때까지 대기 → LoadBalancer 외부 IP 확보
        ↓
 ⑥  확보한 주소를 env.stg.json 의 test.baseUrl 에 자동 기록
```

**Argo CD UI 에서 확인** — 애플리케이션 카드가 `Synced` / `Healthy` (초록)로 바뀌는 것을 보세요.

```powershell
kubectl get application myapp-stg -n argocd
kubectl get svc myapp -n myapp-stg      # EXTERNAL-IP 확인
```

## 2-6. STEP 5~7 — 테스트 3단계

```powershell
pwsh -File .\50_test_unit.ps1
pwsh -File .\60_test_integration.ps1    # env.stg.json 의 baseUrl 을 자동 사용
pwsh -File .\70_test_e2e.ps1
```

## 2-7. STEP 8 — GitOps 검증 (이 환경의 하이라이트)

```powershell
pwsh -File .\80_verify.ps1
```

| 검증 항목 | 의미 |
| --- | --- |
| Argo CD `sync = Synced` | Git 과 클러스터가 일치 |
| Argo CD `health = Healthy` | 워크로드가 정상 |
| readyReplicas ≥ 2 | 요청한 만큼 떠 있음 |
| **배포 이미지 = 최신 빌드 태그** | Git 에 쓴 것이 실제로 반영됨 |
| **selfHeal 드리프트 복구** | **레플리카를 1로 강제 변경 → Argo CD 가 자동으로 2로 복구** |

> 🎯 **마지막 항목이 GitOps 의 본질입니다.** 누가 `kubectl` 로 손대도 클러스터가 **Git 상태로 스스로 돌아옵니다.** 스크립트가 실제로 레플리카를 바꿔 보고 복구되는지 확인합니다.

## 2-8. STEP 9 — 정리 (필수)

```powershell
pwsh -File .\90_cleanup.ps1             # 'yes' 입력
az group exists -n rg-myapp-stg         # false 가 되면 완료
```

## 2-9. stg 문제 해결

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| `acr check-name` 실패 | ACR 이름이 이미 사용 중 | `env.stg.json` 의 `acrName` 뒤에 난수를 붙이기 |
| Application 이 `Unknown` | `repoUrl` 이 잘못됨 / 저장소 비공개 | URL 확인, 비공개면 Argo CD 에 자격 증명 등록 |
| `OutOfSync` 인데 안 바뀜 | 원격에 push 하지 않음 | `git push` 확인 → UI 에서 **Refresh** |
| `ImagePullBackOff` | ACR 연결 안 됨 | `az aks update -g rg-myapp-stg -n aks-myapp-stg --attach-acr <acr>` |
| EXTERNAL-IP 가 `<pending>` | LB 프로비저닝 중 | 2~5분 대기. 계속되면 구독 공용 IP 쿼터 확인 |
| Argo CD UI 접속 불가 | port-forward 끊김 | 명령을 새 터미널에서 다시 실행 |

---

# 3부. prd — AKS + PaaS 운영 환경

> ⏱️ 예상 시간 **50~70분**(PostgreSQL·AKS 생성 포함) · 💰 비용 **높음 — 실습 후 즉시 정리**
> 🚦 **전제: stg 검증이 통과되어 있어야 합니다** (`10_prereq.ps1` 이 확인합니다)

## 3-1. 사전 준비

```powershell
cd C:\dev\workspace-igm\advanced-cloud-developer\배포\prd

# DB 관리자 비밀번호 — 12자 이상, 대/소문자·숫자·특수문자 중 3종 이상
$env:PRD_DB_ADMIN_PASSWORD = "Prd-" + [guid]::NewGuid().ToString("N").Substring(0,16) + "!aZ"
```

`config\env.prd.json` 에서 다음을 **전역 고유 값**으로 변경:

| 키 | 규칙 |
| --- | --- |
| `azure.acrName` | 소문자+숫자 5~50자 |
| `azure.data.postgres.name` | 소문자+숫자+하이픈 3~63자 |
| `argocd.repoUrl` | 실제 Git 저장소 |

## 3-2. STEP 1 — 전제조건 점검

```powershell
pwsh -File .\10_prereq.ps1
```

stg 와 다른 점: **공급자 10종**(PostgreSQL·Cache·KeyVault·Storage·Monitor 등) 확인, **DB 관리자 비밀번호 환경 변수** 확인, 그리고 **stg 검증 통과 기록**(`배포\stg\reports\stg_verify_*.json` 의 `fail=0`) 확인.

> ⚠️ stg 기록이 없으면 경고가 나옵니다. **검증되지 않은 것을 운영에 올리지 않는다**는 원칙 때문입니다.

## 3-3. STEP 2 — 인프라 구성 (의존 순서가 곧 실행 순서)

```powershell
pwsh -File .\20_config.ps1              # 확인 프롬프트에 'yes'
```

**6단계로 진행합니다 — «참조당하는 것부터»:**

| 순서 | 만드는 것 | 왜 이 순서인가 |
| --- | --- | --- |
| 1/6 | 리소스 그룹 · **VNet + 서브넷 2개**(aks / data) | 모든 리소스가 놓일 «땅»이 먼저 |
| 2/6 | **Log Analytics · Application Insights** | AKS 가 생성 시점에 워크스페이스를 참조 |
| 3/6 | **Key Vault · 관리 ID · RBAC 역할** | 앱이 비밀에 접근할 «신원»이 먼저 |
| 4/6 | **PostgreSQL 유연한 서버**(영역 중복 HA·백업 14일·공용 차단) · **Redis** · **Storage** | 앱이 붙을 데이터 계층 |
| 5/6 | 접속 정보를 **Key Vault 에 비밀로 저장** | 값이 Git·이미지·설정에 남지 않게 |
| 6/6 | **AKS** (시스템/사용자 노드 풀 · 3개 영역 · 애드온) + **워크로드 ID 연합 자격 증명** | 마지막에 앱 실행 환경 |

> ⏳ 총 15~25분 걸립니다. PostgreSQL(영역 중복 HA)만 5~10분입니다.

**확인**

```powershell
az resource list -g rg-myapp-prd -o table
kubectl get nodes -L topology.kubernetes.io/zone     # 노드가 3개 영역에 분산되어야 함
```

## 3-4. STEP 3 — 빌드

```powershell
pwsh -File .\30_build.ps1
```

운영은 **불변 태그**(`prd-<sha>`)만 씁니다. `latest` 를 쓰면 «지금 무엇이 돌고 있는지» 추적할 수 없기 때문입니다. 스크립트는 취약점 스캔 결과 확인 방법도 함께 안내합니다.

## 3-5. STEP 4 — 승격 배포

```powershell
pwsh -File .\40_deploy.ps1              # 확인 프롬프트에 'yes'
```

**4단계로 진행합니다:**

1. **매니페스트 치환** — `serviceaccount.yaml`·`secretprovider.yaml` 의 플레이스홀더를 실제 **clientId / Key Vault 이름 / 테넌트 ID** 로 교체
2. **Git 승격 커밋** — `release(prd): promote <태그>`
3. **Argo CD Application 등록** — 운영은 `syncPolicy.automated` **없음**
4. **동기화 요청 → 롤아웃 대기 → Ingress 주소 확보**

> 🔐 **운영이 stg 와 결정적으로 다른 점** — 자동 동기화를 쓰지 않습니다. Git 에 커밋해도 **사람이 Sync 를 승인해야** 반영됩니다. Argo CD UI 에서 **SYNC** 버튼을 눌러 승인하는 흐름을 직접 확인해 보세요.

## 3-6. STEP 5~7 — 테스트

```powershell
pwsh -File .\50_test_unit.ps1           # 릴리스 게이트
pwsh -File .\60_test_integration.ps1    # Key Vault 주입 + PaaS DB 연결 확인
pwsh -File .\70_test_e2e.ps1            # 읽기 전용 스모크
```

**통합 테스트가 운영에서 특별히 확인하는 것:**

| 확인 | 의미 |
| --- | --- |
| `myapp-secret` 에 `DB_HOST`·`DB_USER`·`DB_PASSWORD`·`REDIS_HOST` 키 존재 | **Key Vault → CSI → Secret** 동기화가 실제로 동작 |
| `/readyz` 200 | 앱이 **PaaS PostgreSQL** 에 TLS 로 실제 연결됨 |
| API 스위트 (**쓰기 비활성**) | 운영 데이터를 오염시키지 않음 |

> ⚠️ `env.prd.json` 의 `test.allowWrite` 는 **false 가 기본**입니다. 쓰기 검증은 stg 에서 끝냅니다.

## 3-7. STEP 8 — 운영 준비 검증

```powershell
pwsh -File .\80_verify.ps1
```

| 축 | 검증 항목 | 통과 기준 |
| --- | --- | --- |
| **가용성** | replicas / **영역 분산** / PDB / HPA | ≥3 · **2개 이상 영역** · 존재 · 존재 |
| **보안** | 워크로드 ID · **불변 태그** · 비루트+읽기전용FS | 구성됨 · `latest` 아님 · 둘 다 true |
| **데이터** | DB **공용 액세스 차단** · HA · 백업 보존 | Disabled · ZoneRedundant · ≥7일 |
| **관측** | Container Insights | 사용 |
| **동작** | `/healthz` `/readyz` `/version` | 모두 200 |
| **복구** | 리비전 이력 | 2개 이상 → **즉시 롤백 가능** |

## 3-8. 롤백 연습 (운영에서 가장 중요한 능력)

```powershell
pwsh -File .\rollback.ps1               # 직전 리비전으로
pwsh -File .\rollback.ps1 -ToRevision 2 # 특정 리비전으로
```

> ⚠️ **GitOps 를 쓸 때의 함정** — `kubectl rollout undo` 로 되돌려도 **Git 의 태그는 그대로**입니다. 다음 Sync 에서 문제 버전이 다시 올라갑니다. 반드시 **Git 의 overlay 태그도 이전 값으로 되돌려 커밋**하세요. 스크립트가 이 점을 경고합니다.

## 3-9. STEP 9 — 정리 (실습 종료 시)

```powershell
pwsh -File .\90_cleanup.ps1             # 'yes' 입력
az keyvault purge -n <kv-이름>          # Key Vault 는 소프트 삭제로 남으므로 별도 제거
az group exists -n rg-myapp-prd         # false 확인
```

> 💰 **정리하지 않으면 계속 과금됩니다** — AKS 노드·PostgreSQL(HA는 2배)·Redis·공용 IP·Log Analytics 수집량이 모두 시간당/용량당 과금 대상입니다.

## 3-10. prd 문제 해결

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| `20_config` 가 PostgreSQL 에서 실패 | 이름 중복 / 비밀번호 규칙 위반 | 이름 변경 · 비밀번호 12자+3종 조합 확인 |
| 파드가 `CreateContainerConfigError` | Key Vault CSI 가 비밀을 못 가져옴 | 워크로드 ID 연합 자격 증명·RBAC 역할 전파(수 분) 확인 |
| `/readyz` 503 | DB 연결 실패 | `DB_SSL=true` 확인 · Private 연결 시 DNS 확인 |
| Ingress 주소가 안 나옴 | 앱 라우팅 애드온 미설치 | `az aks enable-addons -a web_application_routing` |
| 파드가 한 영역에 몰림 | 노드 풀 영역 미지정 | 사용자 노드 풀의 `--zones` 확인 |
| Argo CD 가 Sync 안 됨 | 운영은 **수동 Sync** | UI 에서 SYNC 버튼 클릭(정상 동작) |

---

# 4부. 환경 승격(Promotion)과 운영 규칙

## 4-1. 승격 흐름

```
   [dev]                     [stg]                          [prd]
   로컬 k3d                  AKS + Argo CD 자동             AKS + PaaS · 수동 승인
   ────────                 ──────────────                ─────────────────
   빠른 반복                 배포 방식 검증                  가용성·보안·복구
   자유롭게 배포             selfHeal 로 드리프트 교정        사람이 Sync 승인
   쓰기 테스트 허용          쓰기 테스트 허용                 읽기 전용 스모크
        │                          │                              │
        └──── 단위·통합·E2E ───────┴──── 전 검증 Pass ────────────┘
                                      게이트: stg_verify.fail == 0
```

## 4-2. 게이트 규칙 (무엇이 통과해야 다음으로 가나)

| 승격 | 통과 조건 | 확인 방법 |
| --- | --- | --- |
| dev → stg | 단위·통합·E2E 전부 Pass · `dev_verify` fail=0 | `배포\dev\reports\dev_verify_*.json` |
| stg → prd | 위 + **Synced/Healthy** + **selfHeal 복구 확인** | `배포\stg\reports\stg_verify_*.json` (자동 확인됨) |
| prd 반영 | 위 + **사람의 Sync 승인** + 롤백 경로 확보 | Argo CD UI · `rollback.ps1` |

## 4-3. 환경별 «절대 하지 말 것»

| 환경 | 금지 | 이유 |
| --- | --- | --- |
| dev | 실제 개인정보·운영 데이터 사용 | 로컬은 보호 장치가 없음 |
| stg | Secret 을 Git 에 커밋 | GitOps 저장소가 곧 유출 경로가 됨 |
| prd | `latest` 태그 · 자동 Sync · 쓰기 스모크 · 무단 `kubectl` 변경 | 추적 불가 · 검증 없는 반영 · 데이터 오염 · 드리프트 |

## 4-4. 산출물 위치

| 경로 | 내용 |
| --- | --- |
| `배포\<env>\reports\<env>_prereq_*.json` | 전제조건 점검 |
| `배포\<env>\reports\last-build.json` | 직전 빌드 이미지·태그·git sha |
| `배포\<env>\reports\<env>_unit/integration/e2e_*.json` | 테스트 3단계 결과 |
| `배포\<env>\reports\<env>_verify_*.json` | 환경별 검증 결과 (**승격 게이트**) |
| `배포\<env>\reports\<env>_pipeline_*.json` | 전체 파이프라인 요약 |
| `배포\prd\reports\infra-state.json` | Key Vault·clientId·DB 호스트 등 인프라 상태 |
| `<앱>\test\e2e\캡처\<env>_01~04_*.png` | 환경별 E2E 화면 캡처 |

---

# 5부. 전체 체크리스트

## 5-1. dev

| 확인 | 상태 |
| --- | --- |
| Docker Desktop 실행 · k3d·kubectl·node 설치 | ⬜ |
| `10_prereq` 전 항목 Pass | ⬜ |
| k3d 클러스터 생성 · postgres Running | ⬜ |
| 이미지 빌드 + k3d 반입 성공 | ⬜ |
| <http://localhost:8080> 접속 확인 | ⬜ |
| 단위·통합·E2E 3단계 모두 Pass | ⬜ |
| `80_verify` — **배포 버전 = 빌드 태그** 일치 | ⬜ |
| E2E 캡처 `dev_01~04` 생성 | ⬜ |
| **클러스터 정리 완료** | ⬜ |

## 5-2. stg

| 확인 | 상태 |
| --- | --- |
| `acrName`·`repoUrl` 변경 · Git 원격 push 완료 | ⬜ |
| `az login` · 공급자 등록 확인 | ⬜ |
| AKS·ACR 생성 · Argo CD 설치 · Application 등록 | ⬜ |
| `az acr build` 로 이미지 푸시 | ⬜ |
| **overlay 태그 커밋 → Argo CD Synced/Healthy** | ⬜ |
| LoadBalancer 외부 IP 로 접속 확인 | ⬜ |
| 단위·통합·E2E 3단계 모두 Pass | ⬜ |
| **selfHeal 드리프트 복구 검증 통과** | ⬜ |
| **리소스 그룹 삭제 완료** | ⬜ |

## 5-3. prd

| 확인 | 상태 |
| --- | --- |
| stg 검증 통과 기록 존재 | ⬜ |
| `PRD_DB_ADMIN_PASSWORD` 설정 · 이름 3종 변경 | ⬜ |
| 네트워크→관측→보안→데이터→AKS 순서로 구성 완료 | ⬜ |
| 노드가 **3개 영역**에 분산 | ⬜ |
| 불변 태그(`prd-<sha>`)로 빌드 | ⬜ |
| 매니페스트 치환 → Git 승격 커밋 → **수동 Sync 승인** | ⬜ |
| **Key Vault → Secret 주입 확인** (DB_HOST 등 4키) | ⬜ |
| PaaS PostgreSQL 연결 (`/readyz` 200) | ⬜ |
| E2E 스모크 **읽기 전용**으로 Pass | ⬜ |
| `80_verify` 가용성·보안·데이터·관측·복구 전 항목 Pass | ⬜ |
| **롤백 연습 수행** (`rollback.ps1`) | ⬜ |
| **리소스 그룹 + Key Vault purge 완료** | ⬜ |

---

## 부록. 명령 빠른 참조

```powershell
# ── dev ────────────────────────────────────────────────
cd 배포\dev ; pwsh -File .\run_all.ps1
kubectl config use-context k3d-myapp-dev
kubectl logs -n myapp-dev -l app=myapp --tail=100 -f

# ── stg ────────────────────────────────────────────────
cd 배포\stg ; pwsh -File .\run_all.ps1
kubectl get application -n argocd
kubectl port-forward svc/argocd-server -n argocd 8090:443
argocd app sync myapp-stg                      # argocd CLI 사용 시

# ── prd ────────────────────────────────────────────────
cd 배포\prd ; pwsh -File .\10_prereq.ps1
kubectl get pods -n myapp-prd -o wide
kubectl rollout history deploy/myapp -n myapp-prd
pwsh -File .\rollback.ps1

# ── 공통 진단 ───────────────────────────────────────────
kubectl describe pod <파드명> -n <네임스페이스>     # 이벤트에서 실패 원인 확인
kubectl get events -n <네임스페이스> --sort-by=.lastTimestamp
kubectl top pods -n <네임스페이스>                  # 메트릭 서버 필요
```
