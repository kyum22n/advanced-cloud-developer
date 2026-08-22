# 배포 — dev · stg · prd 3환경 파이프라인

> 3차시 「나만의 업무 앱 만들기」에서 만든 앱을 **로컬 → 검증 → 운영** 순서로 올리는 실행 스크립트 모음입니다.
> 📘 **따라하기 가이드**: [`가이드/배포_가이드_dev_stg_prd.md`](가이드/배포_가이드_dev_stg_prd.md)

## 한눈에

| | **dev** | **stg** | **prd** |
| --- | --- | --- | --- |
| 목적 | 빠르게 만들고 빠르게 버린다 | **배포 방식**을 검증한다 | **가용성·보안·복구**가 기본값 |
| 위치 | 내 PC (Docker Desktop) | Azure | Azure |
| 런타임 | k3d | AKS (Free) | AKS (Standard · 3영역) |
| 배포 | `kubectl apply` | **Argo CD 자동**(selfHeal) | **Argo CD 수동 승인** |
| DB | in-cluster PostgreSQL | in-cluster PostgreSQL | **PaaS PostgreSQL**(HA·백업) |
| 비밀 | `kubectl secret` | `kubectl secret` | **Key Vault + CSI + 워크로드 ID** |
| 쓰기 테스트 | 허용 | 허용 | **금지(읽기 전용)** |
| 비용 | 0 | 낮음 | 높음 |

## 세 환경 모두 같은 9단계

```
10 전제조건 → 20 구성 → 30 빌드 → 40 배포 → 50 단위 → 60 통합 → 70 E2E → 80 검증 → 90 정리
```

파일명이 세 환경에서 **완전히 동일**하므로, 한 환경을 익히면 나머지는 «무엇이 달라지는가»만 보면 됩니다.

## 빠른 시작

```powershell
# 1) 로컬 개발 환경 — 비용 0, 15분
cd 배포\dev  ; pwsh -File .\run_all.ps1

# 2) 검증 환경 — config/env.stg.json 의 acrName·repoUrl 을 먼저 변경
cd 배포\stg  ; pwsh -File .\run_all.ps1

# 3) 운영 환경 — stg 검증 통과 후, $env:PRD_DB_ADMIN_PASSWORD 설정 후
cd 배포\prd  ; pwsh -File .\10_prereq.ps1
```

## 폴더 구조

```
배포/
├── README.md                     ← 현재 문서
├── 가이드/배포_가이드_dev_stg_prd.md   ← 따라하기 가이드 (전체 절차·문제 해결·체크리스트)
├── common/
│   ├── lib.ps1                   공통 함수 (로깅·검증·리포트·파괴적 작업 확인)
│   └── app/                      공통 샘플 앱 (myapp 이 없을 때 자동 사용)
│       ├── src/lib/summary.js    순수 로직 (단위 테스트 대상)
│       ├── src/server.js         /healthz /readyz /version /api/*
│       ├── test/unit             단위 6건
│       ├── test/integration      통합 6건
│       ├── test/e2e              E2E 4건 (Playwright · 캡처)
│       └── Dockerfile            멀티스테이지 · 비루트 · HEALTHCHECK
├── dev/   10~90 + run_all + config/k8s/
├── stg/   10~90 + run_all + config/{k8s(base·overlays), argocd}/
└── prd/   10~90 + run_all + rollback + config/{k8s, argocd, infra}/
```

## 앱 소스는 자동으로 결정됩니다

| 우선순위 | 경로 | 조건 |
| --- | --- | --- |
| 1 | `-AppPath` 로 지정한 경로 | 명시 지정 시 |
| 2 | `실습산출물\3차시\myapp` | `Dockerfile` 이 있으면 |
| 3 | `배포\common\app` | 위 둘이 없으면 (샘플 앱) |

## ⚠️ 실행 전 필독

- **stg·prd 는 시간당 과금**됩니다. 각 환경의 `90_cleanup.ps1` 을 **반드시** 실행하세요.
- **Secret 은 Git 에 커밋하지 않습니다.** 비밀번호는 환경 변수 또는 Key Vault 로만 전달합니다.
- **파괴적 작업(삭제)** 은 `yes` 입력 확인을 거칩니다. `-Force` 는 자동화 시에만 쓰세요.
- prd 는 **stg 검증 통과 기록**(`배포\stg\reports\stg_verify_*.json`, fail=0)이 있어야 진행합니다.
