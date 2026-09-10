# 구축 — Terraform 기반 Azure 인프라

> ⛔ **이 폴더의 어떤 스크립트도 자동으로 실행되지 않습니다.**
> 모든 `apply` 는 사람이 계획을 읽고 확인 프롬프트에 응답한 뒤에만 수행됩니다.
> 설계 근거: [`설계/08_인프라_설계서.md`](../설계/08_인프라_설계서.md)

---

## 1. 구조

```
구축/
├── terraform/
│   ├── modules/                 재사용 단위 — 환경을 모른다
│   │   ├── naming/              이름 규칙 · 태그 생성
│   │   ├── network/             VNet · 서브넷 · NSG · 프라이빗 DNS
│   │   ├── identity/            앱별 관리 ID · 최소 권한 역할
│   │   ├── observability/       Log Analytics · App Insights · 예산
│   │   ├── platform/            Container Registry · Key Vault
│   │   ├── messaging/           Service Bus(큐) · Event Hubs(스트림)
│   │   ├── data/                Redis · Cosmos(NoSQL·Mongo) · Data Lake
│   │   ├── springapps/          Azure Spring Apps + 6개 앱
│   │   ├── gateway/             Application Gateway + WAF
│   │   └── private_endpoint/    프라이빗 엔드포인트 공통
│   │
│   ├── envs/                    환경별 «조립» — 리소스를 직접 선언하지 않는다
│   │   ├── dev/  stg/  prd/     main · variables · outputs · backend · tfvars.example
│   │
│   └── shared/bootstrap/        상태 저장소 (딱 한 번 · 로컬 상태)
│
└── scripts/
    ├── lib.ps1                  공통 함수 · 확인 프롬프트 · 결과 기록
    ├── validate_terraform.py    ★ 도구 없이 도는 정적 검증기 (7항목)
    ├── 10_prereq.ps1            전제 확인            (읽기)
    ├── 20_validate.ps1          정적 검증            (읽기)
    ├── 30_plan.ps1              실행 계획 생성       (읽기)
    ├── 40_apply.ps1             인프라 적용          ⚠️ 변경
    ├── 80_verify.ps1            배포 검증            (읽기)
    ├── 90_cleanup.ps1           리소스 정리          ⚠️ 삭제
    └── run_all.ps1              절차 안내 (apply 는 실행하지 않음)
```

---

## 2. 절차

```
 ①  10_prereq    전제 확인      도구 · 로그인 · 공급자 등록 · tfvars
 ②  20_validate  정적 검증      fmt · 자체 검증기 · validate · tflint · checkov
 ③  30_plan      계획 생성      ★ 사람이 «반드시 읽는다»
 ④  (사람)       계획 검토      데이터 삭제 · 재생성 · 예상 밖 리소스 확인
 ⑤  40_apply     적용           확인 프롬프트에 'yes' 입력 필요
 ⑥  80_verify    배포 검증      리소스 · 아이덴티티 · 네트워크 · 태그
 ⑦  90_cleanup   정리 (선택)    ⚠️ 데이터가 사라진다
```

```bash
cd 드론배달/구축/scripts

pwsh ./10_prereq.ps1   -Env dev
pwsh ./20_validate.ps1 -Env dev
pwsh ./30_plan.ps1     -Env dev     # ← 출력을 직접 읽으세요
pwsh ./40_apply.ps1    -Env dev     # ← 확인 프롬프트
pwsh ./80_verify.ps1   -Env dev
```

### 2.1 ③단계에서 반드시 볼 것

| 확인 | 왜 |
| --- | --- |
| **데이터 저장소가 `destroy` 목록에 있는가** | Cosmos·Redis·Storage 가 지워지면 데이터가 사라진다 |
| `forces replacement` 표시가 있는가 | 재생성은 곧 삭제 후 생성이다 |
| 예상하지 않은 리소스가 있는가 | 포털에서 누가 수동으로 바꾼 흔적(드리프트) |
| 비밀이 평문으로 보이는가 | `sensitive = true` 누락 |
| 태그가 빠진 리소스가 있는가 | 비용을 서비스별로 나눌 수 없게 된다 |

`30_plan.ps1` 이 이 항목들을 자동으로 요약해 보여 주지만,
**«요약을 보는 것»과 «계획을 읽는 것»은 다릅니다.** 요약은 놓칠 수 있습니다.

---

## 3. 최초 1회 — 상태 저장소 부트스트랩

```bash
cd 드론배달/구축/terraform/shared/bootstrap
terraform init
terraform apply -var subscription_id=<구독ID> -var owner=<담당자>
```

이것만 **로컬 상태**를 씁니다 — 상태를 저장할 곳을 만드는 중이라 원격 상태를 쓸 수 없습니다.

만들어지는 것:

| 리소스 | 설정 | 이유 |
| --- | --- | --- |
| Storage 계정 | GRS · 버전 관리 · 90일 보존 | 상태 소실 = 인프라 통제 상실 |
| | **공유 키 비활성** | Entra 인증만 허용 (`use_azuread_auth`) |
| 삭제 잠금 | `CanNotDelete` | 실수로 지우지 못하게 |

> ⚠️ **상태 파일에는 비밀이 평문으로 남을 수 있습니다.** 이 저장소를 «비밀처럼» 다루세요.
> 이것이 설계에서 **관리 ID 를 1순위**로 두고 Key Vault 를 2순위로 미룬 이유 중 하나입니다.

---

## 4. 환경 차이 — «구조»가 아니라 «값»

`envs/*/main.tf` 는 세 환경이 **거의 동일**합니다. 차이는 `terraform.tfvars` 의 값뿐입니다.

| 항목 | dev | stg | prd |
| --- | --- | --- | --- |
| VNet | ❌ 공용 엔드포인트 | ✅ 10.2.0.0/16 | ✅ 10.1.0.0/16 + 허브 피어링 |
| PaaS 공용 접근 | 허용 | **차단** | **차단** |
| Service Bus | Basic | Premium | Premium |
| Event Hubs | Basic (2 파티션) | Standard (8) | Premium (**16**) |
| Redis | Basic C0 | Standard C1 | **Premium P1 · 영역 중복 · AOF** |
| Cosmos DB | 서버리스 | 자동 확장 1,000 RU | 자동 확장 4,000 RU · 영역 중복 |
| Storage | LRS | LRS | **GRS** |
| 인스턴스 | 각 1 | 1~2 | **각 2** |
| 추적 샘플링 | 100 % | 50 % | **10 %** |
| 로그 보존 | 30일 | 30일 | **90일** |
| Key Vault 영구삭제 방지 | ❌ | ❌ | **✅** |
| WAF | ❌ | 감지 모드 | **차단 모드** |
| 월 예산 경고 | 100 | 400 | 2,000 |

### 4.1 dev 만 구조가 다른 이유

VNet 은 «규모»가 아니라 «구조» 차이입니다. 원칙에 어긋나지만 의도적입니다.

- **비용** — 프라이빗 엔드포인트 7개 + Premium SKU 강제는 dev 에 과하다
- **대가** — dev 에서 «네트워크 문제»를 잡을 수 없다
- **보완** — **stg 가 prd 와 동일한 네트워크 구조**를 갖는다. stg 의 존재 이유가 이것이다

> 반면 **워크로드 ID 는 dev 에서도 씁니다.** 여기서 타협하면
> «prd 에서만 나는 인증 오류»를 배포 직전에 만나게 됩니다.

---

## 5. 운영(prd) 승격 조건

`10_prereq.ps1 -Env prd` 가 자동으로 확인합니다.

| # | 조건 | 확인 방법 |
| --- | --- | --- |
| ① | **stg 검증 통과 기록** (`stg_verify_*.json` 의 `fail = 0`) | 파일로 검증 — 기억이 아니라 기록 |
| ② | 계획에 데이터 저장소 삭제 없음 | `30_plan.ps1` 이 🛑 로 표시 |
| ③ | 운영 담당자 승인 | `40_apply.ps1` 이 두 번 확인 |

---

## 6. 정적 검증기 (`validate_terraform.py`)

`terraform validate` 는 프로바이더 다운로드(`init`)와 Terraform 1.9+ 가 필요합니다.
이 검증기는 **파이썬만 있으면** 돌아가는 최소 방어선입니다.

| # | 검사 | 잡는 실수 |
| --- | --- | --- |
| ① | 모듈 참조 | 없는 모듈을 부른다 |
| ② | 변수 선언 | 모듈에 없는 인수를 넘긴다 / 필수 변수를 빠뜨린다 |
| ③ | 출력 참조 | 모듈에 없는 출력을 읽는다 |
| ④ | 필수 변수 | `tfvars.example` 에 필수 변수가 빠졌다 |
| ⑤ | **보안 규칙** | `0.0.0.0/0` · `latest` · Contributor · 구독 범위 · 하드코딩 비밀 · ACR 관리자 계정 |
| ⑥ | 태그 | 비용 추적이 안 되는 리소스 |
| ⑦ | 드리프트 | `timestamp()` — plan 마다 전 리소스가 변경 대상이 된다 |

```bash
python 드론배달/구축/scripts/validate_terraform.py
```

**현재 결과: 10개 모듈 · 3개 환경 · 7항목 전부 통과**

---

## 7. 알려진 제약 — 정직하게

| 항목 | 현재 상태 |
| --- | --- |
| `terraform validate` | ⚠️ **실행하지 못했습니다.** 이 구성은 azurerm 4.x 를 쓰므로 Terraform **1.9 이상**이 필요한데, 검증 환경의 Terraform 은 1.6.3 이었습니다. `terraform fmt -recursive -check` 와 자체 검증기 7항목은 통과했습니다. |
| `terraform plan` | ⚠️ 실행하지 않았습니다 — Azure 구독 연결이 필요하고, 본 과제는 **실제 실행을 하지 않는 것**이 전제입니다(CON‑06). |
| `tflint` · `checkov` | 설치되어 있지 않아 건너뛰었습니다. `20_validate.ps1` 이 있으면 자동 실행합니다. |
| Spring Apps 리소스 이름 | `azurerm_spring_cloud_*` 는 azurerm 4.x 에서 여전히 제공되지만, Azure Spring Apps 자체가 은퇴 일정을 가진 서비스입니다. 실제 도입 전에 **현재 지원 상태와 Container Apps 이전 경로**를 확인하세요. |
| 게이트웨이 모듈 | `envs/*` 에서 아직 호출하지 않습니다. TLS 인증서(Key Vault)와 백엔드 FQDN 이 먼저 준비되어야 하므로, 앱 배포 후 2단계로 붙이도록 남겨 두었습니다. |

> 위 항목들을 «통과했다»고 적지 않은 이유 — 검증하지 않은 것을 검증했다고 쓰면
> 그 문서 전체의 신뢰가 사라지기 때문입니다.

---

## 8. 비용 관리

| 조치 | 구현 |
| --- | --- |
| 필수 태그 | `naming` 모듈이 모든 리소스에 `system`·`env`·`owner`·`costCenter`·`managedBy` 부여 |
| 예산 경고 | 실제 80 % · 예측 100 % 에서 이메일 (`observability` 모듈) |
| 자동 계층화 | 이력 Cosmos 30일 TTL → Data Lake 로 이동 (COST‑04) |
| dev 절감 | 서버리스 Cosmos · Basic SKU · 인스턴스 1 |
| **정리** | `90_cleanup.ps1` — 실습 후 반드시 실행 |

> ⚠️ **실습 후 정리를 잊으면 비용이 계속 나갑니다.**
> 특히 Premium SKU(Service Bus·Redis·Event Hubs)와 Application Gateway 는 시간당 과금입니다.

---

## 9. 다음 단계

| 하고 싶은 것 | 문서 |
| --- | --- |
| 왜 이 구조인지 알고 싶다 | [설계/08 인프라 설계서](../설계/08_인프라_설계서.md) |
| 왜 Spring Apps 인지 알고 싶다 | [설계/02 컴퓨팅 플랫폼 선정서](../설계/02_컴퓨팅_플랫폼_선정서.md) |
| 보안 설정의 근거를 알고 싶다 | [설계/09 보안·아이덴티티 설계서](../설계/09_보안_아이덴티티_설계서.md) |
| 배포 후 무엇을 확인하나 | `80_verify.ps1` · [설계/09 §9 검증 케이스](../설계/09_보안_아이덴티티_설계서.md) |
| 애플리케이션을 배포하고 싶다 | [개발/README.md](../개발/README.md) |
| 동작을 검증하고 싶다 | [테스트/README.md](../테스트/README.md) |
