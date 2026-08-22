# 배포 · prd — Azure AKS + PaaS 운영 환경

> **목적**: **가용성 · 보안 · 관측 · 복구가 «기본값»** 인 구성. 데이터는 관리형(PaaS) 서비스가 책임지고, 클러스터는 앱만 실행합니다.
> **전제**: stg 검증 통과 · `az login` · `$env:PRD_DB_ADMIN_PASSWORD` 설정

## ⚠️ 시작 전 반드시 할 일

```powershell
$env:PRD_DB_ADMIN_PASSWORD = Read-Host "PostgreSQL 관리자 비밀번호" -AsSecureString | ConvertFrom-SecureString -AsPlainText
# config/env.prd.json 에서 acrName · postgres.name · argocd.repoUrl 을 전역 고유 값으로 변경
```

## 실행 순서

```powershell
cd 배포\prd
pwsh -File .\10_prereq.ps1            # 구독·공급자·이름·stg 검증 기록 확인
pwsh -File .\20_config.ps1            # 네트워크 → 관측 → 보안 → PaaS 데이터 → AKS (의존 순서)
pwsh -File .\30_build.ps1             # ACR 빌드 + 불변 태그 + 스캔 안내
pwsh -File .\40_deploy.ps1            # 매니페스트 치환 → Git 승격 커밋 → Argo CD 수동 Sync
pwsh -File .\50_test_unit.ps1
pwsh -File .\60_test_integration.ps1  # Key Vault 주입·PaaS DB 연결 확인
pwsh -File .\70_test_e2e.ps1          # 읽기 전용 스모크
pwsh -File .\80_verify.ps1            # 가용성·보안·관측·롤백 가능성 종합 검증
pwsh -File .\rollback.ps1             # 문제 시 즉시 롤백
pwsh -File .\90_cleanup.ps1           # 실습 종료 시에만
```

## PaaS 선택 — 왜 이 구성인가

| 역할 | 선택한 서비스 | 왜 |
| --- | --- | --- |
| 관계형 DB | **Azure Database for PostgreSQL 유연한 서버**<br/>(GeneralPurpose · **영역 중복 HA** · 백업 14일 · 공용 액세스 차단) | 클러스터 안 DB는 백업·HA·패치를 직접 져야 함. PaaS가 그것을 대신하고 **PITR로 논리적 손상까지 복구** |
| 캐시 · 세션 | **Azure Cache for Redis (Standard)** | 세션을 외부화해야 파드를 자유롭게 늘리고 줄일 수 있음 |
| 객체 저장 | **Azure Storage (ZRS · 공유 키 비활성화)** | 첨부·리포트 산출물 보관. 계정 키 대신 ID 기반 접근 |
| 비밀 | **Key Vault + CSI 드라이버 + 워크로드 ID** | **Git·이미지·앱 설정 어디에도 비밀 값이 없다** |
| 관측 | **Log Analytics · App Insights · Container Insights · 관리형 Prometheus** | 증상(지연·오류·포화) 기반 경고의 기반 |
| 진입 | **관리형 NGINX(앱 라우팅 애드온) + 내부 LB** | 앱은 내부에만 노출, 외부 진입은 Ingress 한 곳으로 |
| 배포 | **Argo CD (수동 Sync)** | 운영은 «사람이 승인한 뒤에만» 반영 |

## 운영 준비 검증 항목 (`80_verify.ps1`)

| 축 | 검증 |
| --- | --- |
| **가용성** | replicas ≥ 3 · **2개 이상 영역 분산** · PDB · HPA |
| **보안** | 워크로드 ID · **불변 태그(latest 금지)** · 비루트 + 읽기 전용 루트FS · **DB 공용 액세스 차단** · HA · 백업 ≥ 7일 |
| **관측** | Container Insights 사용 |
| **동작** | `/healthz` `/readyz` `/version` |
| **복구** | 리비전 이력 2개 이상 → 즉시 롤백 가능 |

## 환경 승격(promotion) 규칙

```
   dev(로컬)          stg(AKS+ArgoCD)              prd(AKS+PaaS)
   빠른 반복    →     배포 방식 검증        →      승인 후 반영
   자유 배포          자동 동기화(selfHeal)         수동 Sync + 롤백 준비
                      ↑ 여기서 통과하지 못한 것은 prd 로 못 간다
```

`10_prereq.ps1` 은 **stg 검증 통과 기록(`배포/stg/reports/stg_verify_*.json`, fail=0)** 이 있는지 확인합니다.
