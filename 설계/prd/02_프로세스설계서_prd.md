# prd 02. 프로세스 설계서 — 승인 배포 · 검증 · 롤백

> **답하는 질문**: «누가 무엇을 승인해야 운영에 반영되는가, 그리고 어떻게 되돌리는가»
> **stg 와의 결정적 차이**: **자동 동기화가 없다.** 사람이 «지금»을 결정한다.

> ⚠️ **myapp 적용 현황 (2026-08-29)** — myapp은 `skipPaasData=true`로 PostgreSQL을 생성하지 않아, 이 문서의 PostgreSQL 관련 구간(§1 시퀀스의 PG 참여자, PITR 절차, PostgreSQL HA 실패 대응)은 **N/A**입니다. 실제 20 구성 소요시간도 PostgreSQL·Redis 생성이 빠져 설계 예상(25~40분)보다 짧았습니다(Key Vault RBAC 전파 대기·vCPU 쿼터 재시도 포함 약 10분대). 실제 진행 경과는 [`실습산출물/3차시/11_최종검토_대조.md`](../../실습산출물/3차시/11_최종검토_대조.md) §4단계 참고.

---

## 1. 전체 파이프라인

```mermaid
flowchart LR
    G0["stg 검증 통과 기록"] --> A["10 전제조건<br/>+ 승격 게이트"]
    A --> B["20 구성<br/>AKS·PaaS·KeyVault"] --> C["30 빌드<br/>ACR + 스캔"]
    C --> D["40 배포<br/>Git 커밋 → 수동 Sync"]
    D --> E["50 단위"] --> F["60 통합(읽기)"] --> H["70 E2E(읽기)"]
    H --> I["80 검증<br/>가용성·보안·관측성"]
    I --> J{"이상?"}
    J -->|예| R["rollback.ps1"]
    J -->|아니오| K["운영 유지"]
    K -.실습 종료.-> L["90 정리"]
```

---

## 2. 승격 게이트 (10_prereq)

```mermaid
flowchart TD
    A["10_prereq.ps1 시작"] --> B["도구 확인<br/>az·kubectl·git·node"]
    B --> C["Azure 로그인·구독 확인"]
    C --> D["리소스 공급자 등록 확인"]
    D --> E["배포/stg/reports/stg_verify_*.json 탐색"]
    E --> F{"파일 존재?"}
    F -->|아니오| X1["Fail — stg 검증 기록 없음"]
    F -->|예| G["가장 최근 파일 읽기"]
    G --> H{"fail = 0?"}
    H -->|아니오| X2["Fail — stg 검증 미통과"]
    H -->|예| I["env.prd.json 자리표시자 검사"]
    I --> J{"acrName·repoUrl·keyVaultName 변경됨?"}
    J -->|아니오| X3["Fail"]
    J -->|예| P["Pass — prd 진행 허용"]
```

> 🔑 **이것이 «품질 게이트»의 실체입니다.** 문서상의 규칙이 아니라 **스크립트가 파일을 읽어 강제**합니다. stg 를 건너뛰면 prd 는 시작되지 않습니다.

---

## 3. 구성 프로세스 (20_config) — 의존 순서

```mermaid
sequenceDiagram
    participant S as 20_config.ps1
    participant AZ as Azure
    participant KV as Key Vault
    participant PG as PostgreSQL
    participant K as AKS

    S->>AZ: group create rg-myapp-prd
    S->>AZ: acr create (Premium)
    S->>AZ: aks create --tier standard<br/>--zones 1 2 3 (시스템 풀)<br/>--enable-oidc-issuer --enable-workload-identity<br/>--enable-addons monitoring --attach-acr
    Note over AZ: 10~20분
    S->>AZ: aks nodepool add (사용자 풀 · 3영역)
    S->>KV: keyvault create (RBAC 권한 모델)
    S->>S: PRD_DB_PASSWORD 읽기<br/>없으면 32자 난수 생성 (출력 안 함)
    S->>KV: secret set db-password
    S->>PG: flexible-server create<br/>--high-availability ZoneRedundant<br/>--backup-retention 14 --storage-size 128
    Note over PG: 10~15분
    S->>PG: 공용 네트워크 액세스 차단 (snet-data 전용)
    S->>PG: db create appdb
    S->>K: aks get-credentials
    S->>K: enable-addons azure-keyvault-secrets-provider
    S->>S: 사용자 할당 관리 ID 생성
    S->>KV: role assignment "Key Vault Secrets User"
    S->>K: federated-credential create<br/>(OIDC 발급자 ↔ ServiceAccount myapp-sa)
    S->>K: apply namespace · serviceaccount · SecretProviderClass · ConfigMap
    S->>K: Argo CD 설치 (syncPolicy 없음 = 수동)
```

### 3-1. 순서가 중요한 이유

| 선행 | 후행 | 이유 |
| --- | --- | --- |
| AKS OIDC 발급자 활성화 | 연합 자격 증명 생성 | 발급자 URL 이 있어야 연합 설정 가능 |
| 관리 ID 생성 | Key Vault 역할 부여 | 대상 주체가 있어야 역할 할당 |
| Key Vault 시크릿 저장 | SecretProviderClass 적용 | 없는 시크릿을 마운트하면 파드 기동 실패 |
| VNet·서브넷 생성 | AKS · PostgreSQL | 앱(snet-aks)·데이터(snet-data) 계층을 분리 배치 |

---

## 4. 빌드 프로세스 (30_build)

```mermaid
sequenceDiagram
    participant S as 30_build.ps1
    participant ACR as ACR (Premium)
    participant SC as 취약점 스캔

    S->>S: git SHA 확인
    alt SHA 없음 (Git 미초기화)
        S->>S: 경고 — 추적성 저하
    end
    S->>ACR: az acr build -t myapp:prd-<sha>
    Note over ACR: prd 는 가변 태그(latest 등) 병행 금지
    ACR-->>S: 성공
    S->>SC: 스캔 결과 조회 (Defender 연동 시)
    SC-->>S: 심각도 요약 (참고)
    S->>S: reports/last-build.json 기록
```

| prd 태그 규칙 | 근거 |
| --- | --- |
| **`prd-<sha>` 만 사용** | 불변 태그 — «어느 코드가 돌고 있는가»가 항상 명확 |
| `latest` 등 가변 태그 **병행 금지** | 롤백 대상 특정 불가 · 재현 불가 |

---

## 5. 배포 프로세스 (40_deploy) — 수동 승인

```mermaid
sequenceDiagram
    participant O as 운영자
    participant S as 40_deploy.ps1
    participant G as Git 원격
    participant A as Argo CD
    participant K as AKS

    S->>S: last-build.json 읽기
    S->>S: overlays/prd/kustomization.yaml 의 newTag 갱신
    S->>G: commit "deploy(prd): image tag prd-<sha>" + push
    S->>O: 배포 대상 요약 표시<br/>(이미지·태그·SHA·대상 클러스터)
    O-->>S: 확인 입력 (yes)
    Note over O,S: ⚠️ 이 승인이 stg 와의 결정적 차이
    S->>A: argocd app sync myapp-prd (명시적 요청)
    A->>G: 저장소 조회
    A->>K: 매니페스트 적용
    K->>K: 롤링 업데이트<br/>maxSurge 1 · maxUnavailable 0
    loop 최대 600초
        S->>A: Synced AND Healthy?
        A-->>S: 상태
    end
    S->>K: 내부 LB 주소 조회
    S->>S: env.prd.json 의 test.baseUrl 기록
```

### 5-1. 배포 중 가용성

| 시점 | 준비된 파드 | 사용자 영향 |
| --- | --- | --- |
| t0 | 구 3 | 없음 |
| t1 | 구 3 + 신 1(준비 중) | 없음 |
| t2 | 구 2 + 신 1 | 없음 (PDB minAvailable 2 유지) |
| t3~ | 점진 교체 | 없음 |
| tN | 신 3 | 없음 |

> **`maxUnavailable: 0` + `minAvailable: 2` 조합으로 가용 파드가 2 미만으로 내려가지 않습니다.**

---

## 6. 검증 프로세스 (80_verify)

```mermaid
flowchart TD
    A["가용성"] --> A1["readyReplicas >= 3"]
    A --> A2["영역 분산 >= 2 zone"]
    A --> A3["PDB minAvailable 충족"]
    A --> A4["HPA 활성"]
    B["보안"] --> B1["비루트 실행"]
    B --> B2["불변 태그(latest 금지)"]
    B --> B3["Key Vault CSI 마운트 성공"]
    B --> B4["DB TLS(DB_SSL=true)"]
    B --> B5["평문 비밀 미노출"]
    C["기능"] --> C1["/healthz /readyz /version 200"]
    C --> C2["배포 이미지 = 빌드 태그"]
    D["관측성"] --> D1["Container Insights 활성"]
    D --> D2["최근 로그 수집 확인"]
    A1 & A2 & A3 & A4 & B1 & B2 & B3 & B4 & B5 & C1 & C2 & D1 & D2 --> R["prd_verify_*.json"]
```

---

## 7. 롤백 프로세스 (rollback.ps1)

```mermaid
flowchart TD
    S["장애 인지"] --> T{"영향 범위?"}
    T -->|"앱 버전 문제"| A["rollback.ps1 실행"]
    T -->|"데이터 문제"| B["PostgreSQL PITR<br/>(별도 절차 · 신중)"]
    T -->|"인프라 문제"| C["노드 풀·클러스터 진단"]

    A --> A1["직전 성공 태그 확인<br/>(Git 이력 · ACR 태그 목록)"]
    A1 --> A2["overlays/prd newTag = 직전 태그"]
    A2 --> A3["git commit + push"]
    A3 --> A4["확인 입력 (yes)"]
    A4 --> A5["argocd app sync"]
    A5 --> A6["Synced/Healthy 대기"]
    A6 --> A7["/healthz /version 확인"]
    A7 --> A8{"복구?"}
    A8 -->|예| OK["종료 · 원인 분석 착수"]
    A8 -->|아니오| ESC["에스컬레이션"]
```

### 7-1. 롤백 방식 비교

| 방식 | 속도 | 이력 | prd 적합성 |
| --- | --- | --- | --- |
| **`rollback.ps1` (Git 태그 되돌림 + sync)** | 보통(2~5분) | ✅ 남음 | ✅ **권장** |
| `git revert` + sync | 보통 | ✅ 남음 | ✅ 가능 |
| `kubectl rollout undo` | 빠름 | ❌ Git 과 불일치 | ⚠️ 긴급 시만 · 이후 Git 정합 필요 |
| 클러스터 재생성 | 매우 느림 | – | ❌ 부적합 |

> ⚠️ **`kubectl rollout undo` 를 쓰면 Git 과 클러스터가 어긋납니다.** prd 는 수동 동기화이므로 selfHeal 이 즉시 되돌리지는 않지만, **다음 sync 때 문제가 재현**됩니다. 반드시 Git 을 함께 맞추세요.

### 7-2. 롤백 판단 기준

| 신호 | 조치 |
| --- | --- |
| `/healthz` 실패율 상승 | 즉시 롤백 |
| 5xx 급증 (App Insights) | 즉시 롤백 |
| `CrashLoopBackOff` 발생 | 즉시 롤백 |
| 응답 시간 악화(임계 초과) | 원인 확인 후 판단 |
| 특정 기능만 오류 | 영향도 평가 후 판단 |

---

## 8. 실패 처리 매트릭스

| 단계 | 증상 | 원인 | 조치 |
| --- | --- | --- | --- |
| 10 | stg 검증 기록 없음 | stg 미수행 | **stg 파이프라인부터 수행** |
| 20 | AKS 생성 실패 | vCPU 쿼터 부족 | 쿼터 증설 또는 노드 크기 하향 |
| 20 | PostgreSQL HA 실패 | Burstable 계층 선택 | **GeneralPurpose 이상**으로 변경 |
| 20 | 연합 자격 증명 실패 | OIDC 발급자 미활성 | `az aks update --enable-oidc-issuer` |
| 40 | 파드 `CreateContainerConfigError` | SecretProviderClass 마운트 실패 | Key Vault 역할 할당·시크릿 이름 확인 |
| 40 | Argo CD `OutOfSync` 유지 | 수동 동기화 미실행 | `argocd app sync` (**정상 동작**) |
| 60 | DB 연결 실패 | 공용 액세스 차단 상태에서 사설 경로 미구성 | 서브넷·사설 DNS 확인 |
| 60 | TLS 오류 | `DB_SSL=false` | ConfigMap 수정 → 커밋 → sync |
| 80 | 영역 분산 미달 | 노드 풀 영역 설정 누락 | 노드 풀 `--zones 1 2 3` 확인 |
| 80 | 관측성 미수집 | monitoring 애드온 미설치 | `az aks enable-addons -a monitoring` |

---

## 9. 소요 시간 기준

| 단계 | 최초 | 재실행 |
| --- | --- | --- |
| 10 전제조건 | 30~60초 | 30초 |
| 20 구성 | **25~40분** (AKS 10~20 + PostgreSQL 10~15) | 1~2분 |
| 30 빌드 | 3~5분 | 2~3분 |
| 40 배포 | 3~8분 (승인 대기 제외) | 2~5분 |
| 50~70 테스트 | 2~4분 | 1~3분 |
| 80 검증 | 1~2분 | 동일 |
| **rollback** | – | **2~5분** |
| 90 정리 | 요청 즉시(백그라운드 10~20분) | – |
| **합계** | **약 40~60분** | **약 8~15분** |
