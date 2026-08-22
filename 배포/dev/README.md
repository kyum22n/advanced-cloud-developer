# 배포 · dev — 로컬 k3d 개발 환경

> **목적**: 내 PC에서 **빠르게 만들고 빠르게 버린다.** 클라우드 비용 없이 배포·테스트 전 과정을 반복합니다.
> **전제**: Docker Desktop 실행 중 · k3d · kubectl · Node.js (1차시 Part A에서 설치)

## 실행 순서

```powershell
cd 배포\dev
pwsh -File .\run_all.ps1            # 전체 파이프라인 한 번에
# 또는 단계별로
pwsh -File .\10_prereq.ps1          # 전제조건 점검
pwsh -File .\20_config.ps1          # k3d 클러스터·ConfigMap·Secret·PostgreSQL
pwsh -File .\30_build.ps1           # 이미지 빌드 + k3d 반입
pwsh -File .\40_deploy.ps1          # 배포 + 롤아웃 대기
pwsh -File .\50_test_unit.ps1       # 단위
pwsh -File .\60_test_integration.ps1# 통합
pwsh -File .\70_test_e2e.ps1        # E2E (Playwright)
pwsh -File .\80_verify.ps1          # 배포 검증
pwsh -File .\90_cleanup.ps1         # 정리 (되돌릴 수 없음)
```

접속: **http://localhost:8080**

## 이 환경의 설계 선택

| 항목 | 선택 | 이유 |
| --- | --- | --- |
| 오케스트레이터 | **k3d** (Docker 안의 경량 k8s) | 설치·삭제가 수 초 · AKS와 같은 `kubectl` 인터페이스 |
| 레지스트리 | **없음** (`k3d image import`) | 로컬 반복에 레지스트리 왕복은 불필요 |
| 데이터베이스 | **in-cluster PostgreSQL** | 버려도 되는 데이터 · 비용 0 |
| 노출 | **NodePort + k3d 포트 매핑** | Ingress 컨트롤러 없이 최단 경로 |
| 비밀 관리 | 환경 변수 → `kubectl create secret` | dev 한정. stg·prd 는 Key Vault 사용 |

## 산출물

| 경로 | 내용 |
| --- | --- |
| `reports/last-build.json` | 직전 빌드 이미지·태그·git sha |
| `reports/dev_unit_*.json` | 단위 테스트 결과 |
| `reports/dev_integration_*.json` | 통합 테스트 결과 |
| `reports/dev_e2e_*.json` | E2E 결과 |
| `reports/dev_verify_*.json` | 배포 검증 결과 |
| `reports/dev_pipeline_*.json` | 전체 파이프라인 요약 |
| `<앱>/test/e2e/캡처/dev_01~04_*.png` | E2E 화면 캡처 |
