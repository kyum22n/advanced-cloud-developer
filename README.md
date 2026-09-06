# Advanced Cloud Developer (매치업 클라우드 Application Developer)

> Azure 위에서 **같은 앱을 5가지 스택으로 만들고, dev → stg → prd 세 환경에 GitOps로 배포하고, 오픈소스 LLM까지 직접 서빙**해 본 클라우드 심화 실습 저장소

## 📌 교육 과정 소개

이 저장소는 **IGM세계경영연구원**과 국내 IT인프라 기업 **메타넷엑스**가 공동 운영하는
**「매치업 클라우드 전문가 양성과정 — Application Developer」** (기본과정 + 심화과정, Microsoft Azure 기반)에서
직접 실습하고 산출한 결과물을 정리한 개인 학습 저장소입니다.

과정은 클라우드 핵심 직무를 **인프라 아키텍처 · DB 솔루션 아키텍처 · Application Developer · 보안 엔지니어** 4개 트랙으로 나누어 진행되며,
그중 **Application Developer** 트랙에서는 Azure 핵심 서비스 이해 → 다중 언어 웹앱 개발 → 컨테이너·쿠버네티스 배포 →
GitOps 운영 → 오픈소스 LLM 배포까지 실제 클라우드 자원(Azure) 위에서 직접 수행했습니다.

이 저장소의 커밋은 실습 중 직접 작성한 코드·설계 문서·배포 스크립트·점검 리포트로 구성되어 있으며,
`실습산출물/` 아래에는 각 차시별로 실제 Azure 자원에 대해 수행한 실습 기록(성공·실패·트러블슈팅 포함)이 O/X 점검표와 함께 남아 있습니다.

## 🛠️ Tech Stack

### Cloud / IaC
- Microsoft Azure (VNet, Bastion, NAT Gateway, VM, Blob Storage, Azure Files, MySQL Flexible Server, Log Analytics, Entra ID/Workload Identity, Key Vault, AKS, ACR)
- Terraform, Azure CLI, AWS CLI(비교 실습)

### Container / Orchestration / GitOps
- Docker (멀티스테이지 · 비루트 이미지)
- Kubernetes — k3d(dev, 로컬) · AKS(stg/prd, Azure)
- Kustomize (base/overlays), Argo CD (automated sync + selfHeal / 수동 승인 배포)

### Backend (동일 API 계약, 3가지 구현)
- Java 17 · Spring Boot 3.3 · Maven
- Node 20 · NestJS 10 · TypeScript(strict)
- Python 3.11 · FastAPI · psycopg3(async)

### Frontend (동일 E2E 계약, 2가지 구현)
- HTML5 바닐라 JS (빌드 없음)
- Vue 3 · Vite

### Database & Security
- PostgreSQL (in-cluster / PaaS), MySQL Flexible Server
- Key Vault + CSI Driver + Workload Identity(Entra ID) 기반 무비밀(secret-less) 인증

### Testing / Static Analysis
- JUnit5 · node:test · pytest, Playwright(E2E)
- ESLint(strict) · Checkstyle/SpotBugs · Ruff/Bandit/mypy(strict)

### LLM Serving
- 공개 가중치 모델(GLM 5.2) · vLLM · GPU 노드 풀(Spot) · AKS

## ✨ 실습 내용 요약

### 1차시 — Azure 기초 인프라
Terraform·Azure CLI·AWS CLI 개발 환경을 구성하고, Entra ID 테넌트·사용자·권한을 다룬 뒤 VNet·Bastion·NAT Gateway·VM 2대를 직접 구축·연결했습니다. 이어서 Blob Storage·Azure Files·MySQL Flexible Server를 구성하고 모니터링(Log Analytics)까지 연동한 뒤, 사용한 리소스를 비용 리포트와 함께 안전하게 정리했습니다.

### 2차시 — 스토리지 실습 보강
Azure Storage Explorer를 활용해 Blob/Files 스토리지를 GUI로 다루는 실습을 진행했습니다.

### 3차시 — 나만의 업무 앱 만들기 (핵심 실습)
하나의 REST API 계약(`/healthz`, `/readyz`, `/version`, `/api/items`, `/api/summary`)을 **Spring Boot·NestJS·FastAPI 3가지 백엔드**와 **HTML5·Vue 2가지 프런트엔드**로 각각 구현하고, **웹 테트리스 게임**(상태 없는 앱, SRS 회전·월킥·홀드 등 실제 룰 구현)을 별도 애플리케이션으로 만들었습니다. 이후 두 앱을 **dev(k3d, 로컬) → stg(AKS + Argo CD GitOps) → prd(AKS 3영역 + PaaS DB + Key Vault)** 3단계 파이프라인에 동일한 9단계 스크립트(`10_prereq ~ 90_cleanup`)로 배포하며, Argo CD의 selfHeal(수동 드리프트를 Git 상태로 자동 복구)까지 실제로 검증했습니다. `runAsNonRoot` UID 오류, nginx 권한 오류, Playwright 설정 누락, kubectl 262KB 어노테이션 한도 등 실제로 마주친 배포 트러블슈팅도 기록했습니다.

### 모델 배포 — 오픈소스 LLM 서빙
업무 앱 배포와 **동일한 원칙과 9단계 스크립트 구조**를 그대로 적용해, 공개 가중치 모델(GLM 5.2)을 vLLM으로 GPU 노드 풀(AKS, Spot·taint·min 0)에 배포하는 설계·비용 최적화·테스트 절차를 수립했습니다. 시크릿 대신 Workload Identity를 쓰고, GPU 시간이 비용의 90% 이상을 차지한다는 점에서 손익분기·정리 자동화를 특히 강조했습니다.

## 🏗️ 시스템 아키텍처

```
[HTML5 / Vue Frontend] ──nginx──┐
                                 │
[Spring Boot / NestJS / FastAPI]┤  동일 OpenAPI 계약(/healthz,/readyz,/version,/api/*)
                                 │
                          [PostgreSQL]

dev  : 내 PC(Docker Desktop) → k3d → kubectl apply → in-cluster Postgres
stg  : Azure AKS(Free) → Argo CD 자동 동기화(prune+selfHeal) → in-cluster Postgres
prd  : Azure AKS(3영역) → Argo CD 수동 승인 → PaaS PostgreSQL(HA·백업) → Key Vault+Workload Identity

모델 서빙 : Azure AKS GPU 노드 풀(Spot) → vLLM → GLM 5.2 (앱과 동일한 워크로드 ID·9단계 스크립트 구조)
```

인증 방식은 **환경이 스스로 선택**합니다 — `DB_PASSWORD`가 없고 워크로드 ID 환경 변수가 있으면 자동으로 `entra`(Azure AD 토큰) 모드로 전환되며, 세 백엔드 구현 모두 이미지는 하나로 동일합니다.

## 📂 프로젝트 구조

```text
advanced-cloud-developer
├── 설계/            # 공통(기능·API·데이터모델·시퀀스·테스트·아이덴티티) + dev/stg/prd 환경별 설계서
├── 개발/            # 백엔드 3종(springboot/nestjs/fastapi) · 프런트 2종(html5/vue) · 정적검증 도구
├── 배포/            # dev/stg/prd 9단계 배포 스크립트(PowerShell), 공통 샘플 앱, 배포 가이드
├── 모델/            # 오픈소스 LLM(GLM 5.2) Azure 배포 설계·비용최적화·k8s 매니페스트
└── 실습산출물/      # 차시별 실제 Azure 실습 기록(점검 리포트, 트러블슈팅, 배포 결과, 테스트 캡처)
    ├── 1차시/      # Terraform/Azure CLI 환경, Entra ID, VNet/Bastion/NAT, Storage/MySQL, 비용정리
    ├── 2차시/      # Azure Storage Explorer 실습
    └── 3차시/      # 나만의 업무 앱 + 웹 테트리스 dev→stg 배포 결과
```

## 🔗 참고

- 교육 과정: [IGM세계경영연구원 — 매치업 클라우드 전문가 양성과정](https://igm.or.kr/digital/link/cloud.php)
