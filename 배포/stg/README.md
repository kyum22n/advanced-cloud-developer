# 배포 · stg — Azure AKS + Argo CD GitOps 검증 환경

> **목적**: 앱이 아니라 **«배포 방식» 자체를 검증**합니다. Git 이 유일한 진실이 되고, 클러스터가 그 상태로 스스로 수렴하는지 확인합니다.
> **전제**: `az login` 완료 · Git 원격 저장소 존재 · 1차시 Part D(Azure CLI) 완료

## ⚠️ 시작 전 반드시 할 일

`config/env.stg.json` 의 두 값을 바꾸세요.

| 키 | 바꿔야 하는 이유 |
| --- | --- |
| `azure.acrName` | **ACR 이름은 전역 고유** — 소문자·숫자 5~50자 |
| `argocd.repoUrl` | Argo CD 가 **감시할 Git 저장소** — 이게 없으면 GitOps 가 동작하지 않음 |

## 실행 순서

```powershell
cd 배포\stg
pwsh -File .\run_all.ps1
# 또는 단계별
pwsh -File .\10_prereq.ps1            # az 로그인·구독·공급자·Git 확인
pwsh -File .\20_config.ps1            # RG·ACR·AKS 생성 → Argo CD 설치 → App 등록
pwsh -File .\30_build.ps1             # az acr build (로컬 Docker 불필요)
pwsh -File .\40_deploy.ps1            # overlay 태그 갱신 → git commit/push → Argo CD 동기화
pwsh -File .\50_test_unit.ps1
pwsh -File .\60_test_integration.ps1
pwsh -File .\70_test_e2e.ps1
pwsh -File .\80_verify.ps1            # Synced/Healthy + selfHeal 드리프트 복구 검증
pwsh -File .\90_cleanup.ps1 -Force    # 리소스 그룹 삭제 (필수)
```

## GitOps 흐름 — 이 환경의 핵심

```
 개발자                 Git 저장소                Argo CD (클러스터 안)         AKS
   │                        │                          │                        │
   │ 30_build (ACR 빌드)    │                          │                        │
   ├───────────────────────►│                          │                        │
   │ 40_deploy: overlay     │                          │                        │
   │  kustomization.yaml    │   폴링/웹훅으로 감지      │                        │
   │  의 newTag 를 갱신 →   ├─────────────────────────►│                        │
   │  commit & push         │                          │  선언 상태와 실제 상태  │
   │                        │                          │  비교 → 차이만 적용     ├──► 배포
   │                        │                          │                        │
   │  (누가 kubectl 로      │                          │  selfHeal 이 Git 상태로 │
   │   손대면)              │                          │  자동 복구             ├──► 원복
```

> **CI 는 이미지를 만들고, CD 는 Git 을 본다.** 파이프라인이 클러스터 자격 증명을 갖지 않으므로 공격면이 줄어듭니다.

## 이 환경의 설계 선택

| 항목 | 선택 | 이유 |
| --- | --- | --- |
| 클러스터 | **AKS (Free 계층 · 2노드)** | 검증 목적이므로 최소 사양 · SLA 불필요 |
| 네트워크 | **Azure CNI Overlay** | IP 소모가 적고 신규 클러스터의 기본 권장 |
| 이미지 빌드 | **`az acr build`** | 로컬 Docker 없이 클라우드에서 빌드·푸시 |
| 배포 방식 | **Argo CD (pull·automated·selfHeal)** | 드리프트 자동 교정 · Git 이력 = 배포 이력 |
| 매니페스트 | **Kustomize base + overlays/stg** | 환경 차이를 «패치»로만 표현 |
| DB | **in-cluster PostgreSQL(StatefulSet)** | stg 는 «배포 방식» 검증이 목적 · PaaS DB 는 prd 에서 |
| 비밀 | `kubectl create secret` (Git 미포함) | **Secret 은 절대 Git 에 커밋하지 않는다** |

## Argo CD UI 접속

```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d   # 초기 비밀번호
kubectl port-forward svc/argocd-server -n argocd 8090:443                                             # https://localhost:8090 (ID: admin)
```
