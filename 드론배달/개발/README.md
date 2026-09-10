# 개발 — Azure Spring Apps 마이크로서비스 · Vue.js UI

> 설계([../설계/](../설계/))를 코드로 옮긴 결과입니다. 각 파일의 «왜»는 코드 주석에 있습니다.
> 실행 방법은 아래 §5, 실습 절차는 [`실습자료/4차시`](../../실습자료/4차시_드론배달_마이크로서비스_개발.md).

---

## 1. 구조

```
개발/
├── 공통/openapi/                   ★ API 계약 — 진실의 원천 (계약 우선)
│   └── drone-delivery.yaml         공개 API 6경로 · 스키마 13종
│
├── services/                       Java 17 · Spring Boot 3.3.4 멀티모듈
│   ├── pom.xml                     부모 POM (의존성 버전 통일)
│   ├── common-contract/            ★ 게시된 언어 — 값 개체 · 이벤트 스키마
│   ├── ingestion/          :8081   배달 요청 수신 · 큐 게시          (공개)
│   ├── workflow/           :8082   Saga 조정 · 감시                  (내부)
│   ├── delivery/           :8083   배달 애그리거트 · 상태 · ETA      (공개)
│   ├── package-service/    :8084   패키지 애그리거트                 (내부)
│   ├── drone-scheduler/    :8085   드론 애그리거트 · 할당 · 위치     (내부)
│   └── delivery-history/   :8086   이력 적재 · 조회 (CQRS 읽기 측)   (공개)
│
└── ui/                             Vue 3 + Vite — 예약 · 추적 · 이력
```

> 🔑 **`공통/openapi/drone-delivery.yaml` 이 계약입니다.** 코드가 이것을 따릅니다.
> 코드에서 생성한 `/v3/api-docs` 와 이 파일이 다르면
> [계약 테스트](../테스트/integration/20_contract.ps1)가 실패해야 합니다.

---

## 2. 검증 결과

| 대상 | 도구 | 결과 |
| --- | --- | --- |
| 백엔드 단위 테스트 | JUnit 5 (Maven Surefire) | **117 통과 · 0 실패 · 0 오류** |
| 프런트엔드 테스트 | Vitest + Vue Test Utils | **12 통과** |
| 프런트엔드 정적 분석 | ESLint (flat config) | **오류 0 · 경고 0** |
| 프런트엔드 빌드 | Vite 6 | 성공 |
| 인프라 정적 검증 | 자체 검증기 7항목 | 통과 |
| 인프라 형식 | `terraform fmt -recursive -check` | 통과 |
| PowerShell 구문 | `Parser::ParseFile` | 14개 파일 오류 0 |

### 2.1 서비스별 테스트

| 모듈 | 테스트 | 무엇을 보장하나 |
| --- | ---: | --- |
| `common-contract` | 26 | 값 개체 불변성 · 상태 기계 전이 규칙 · 이벤트 봉투 직렬화 |
| `delivery` | 30 | **INV‑01·02·04·05·06** · ETA 계산 · 수명 주기 · 아키텍처 규칙 |
| `drone-scheduler` | 18 | **INV‑03**(동시 1배달) · 용량 · 배터리 · 보상 멱등성 · 경합 해소 |
| `workflow` | 17 | **Saga 역순 보상** · 타사 위탁 분기 · Supervisor 시간 초과 |
| `delivery-history` | 11 | 멱등 소비 · 이벤트 순서 · 알 수 없는 이벤트 내성 |
| `package-service` | 8 | 무게·크기 검증 · 드론 적재 가능성 |
| `ingestion` | 7 | **AC‑2 멱등 키** · 본문 해시 대조 |

> ⚠️ **여기서 «통과»가 뜻하는 것** — 도메인 규칙과 서비스 간 계약이 코드에서 지켜진다는 것입니다.
> 실제 Azure 리소스와의 연동은 [`테스트/`](../테스트/) 의 통합·E2E 스크립트가 확인하며,
> 그것은 인프라가 실제로 배포된 뒤에만 실행할 수 있습니다.

---

## 3. 계층 구조와 강제 방법

```
  api/              REST 컨트롤러 · DTO · 예외 처리        ← Spring 의존 OK
  application/      유스케이스 조정 · 포트 정의            ← Spring 의존 OK
  ★ domain/         애그리거트 · 값 개체 · 도메인 서비스   ← 프레임워크 의존 ❌
  infrastructure/   저장소 구현 · 메시징 · ACL             ← Spring 의존 OK
```

**도메인 계층의 순수성은 문서가 아니라 테스트로 강제합니다.**

```java
// delivery/src/test/java/.../ArchitectureRuleTest.java
@Test
@DisplayName("도메인 계층은 프레임워크에 의존하지 않는다")
void domainHasNoFrameworkDependency() { ... }
```

도메인 소스에 `org.springframework` · `jakarta.persistence` · `com.azure.` ·
`io.swagger` · `com.fasterxml.jackson` import 가 하나라도 있으면 **빌드가 실패**합니다.

> 이 규칙이 지켜지면 저장소를 Redis 에서 다른 것으로 바꿔도 도메인 코드는 그대로입니다.
> 깨지면 «DDD 처럼 생겼지만 실제로는 프레임워크에 묶인» 코드가 됩니다.

---

## 4. 핵심 코드 위치

| 개념 | 파일 |
| --- | --- |
| **INV‑01·02·04·05·06** (배달 불변식) | [`delivery/.../domain/Delivery.java`](services/delivery/src/main/java/com/fabrikam/drone/delivery/domain/Delivery.java) |
| **INV‑03** (드론 동시 1배달) | [`drone-scheduler/.../domain/Drone.java`](services/drone-scheduler/src/main/java/com/fabrikam/drone/drone/domain/Drone.java) |
| 상태 기계 (전이 규칙) | [`common-contract/.../vo/DeliveryStatus.java`](services/common-contract/src/main/java/com/fabrikam/drone/contract/vo/DeliveryStatus.java) |
| **Saga 오케스트레이션** | [`workflow/.../service/SchedulerService.java`](services/workflow/src/main/java/com/fabrikam/drone/workflow/service/SchedulerService.java) |
| **Supervisor** (시간 초과 감시) | [`workflow/.../service/SupervisorService.java`](services/workflow/src/main/java/com/fabrikam/drone/workflow/service/SupervisorService.java) |
| **손상 방지 계층 (ACL)** | [`workflow/.../acl/ThirdPartyTransportAdapter.java`](services/workflow/src/main/java/com/fabrikam/drone/workflow/infrastructure/acl/ThirdPartyTransportAdapter.java) |
| 복원력 (재시도·회로차단·격벽) | [`workflow/.../http/HttpAgents.java`](services/workflow/src/main/java/com/fabrikam/drone/workflow/infrastructure/http/HttpAgents.java) · [`application-resilience.yml`](services/workflow/src/main/resources/application-resilience.yml) |
| **멱등 키** (AC‑2) | [`ingestion/.../application/IdempotencyGuard.java`](services/ingestion/src/main/java/com/fabrikam/drone/ingestion/application/IdempotencyGuard.java) |
| **멱등 소비자** | [`workflow/.../DeliveryRequestConsumer.java`](services/workflow/src/main/java/com/fabrikam/drone/workflow/infrastructure/DeliveryRequestConsumer.java) |
| **구체화된 뷰** (읽기 모델) | [`delivery/.../RedisDeliveryRepository.java`](services/delivery/src/main/java/com/fabrikam/drone/delivery/infrastructure/RedisDeliveryRepository.java) |
| 게시된 언어 (이벤트 봉투) | [`common-contract/.../event/DomainEvent.java`](services/common-contract/src/main/java/com/fabrikam/drone/contract/event/DomainEvent.java) |
| 상관 ID 전파 | [`delivery/.../api/CorrelationIdFilter.java`](services/delivery/src/main/java/com/fabrikam/drone/delivery/api/CorrelationIdFilter.java) |
| Problem Details (RFC 9457) | [`delivery/.../api/GlobalExceptionHandler.java`](services/delivery/src/main/java/com/fabrikam/drone/delivery/api/GlobalExceptionHandler.java) |
| Vue 추적 폴링 | [`ui/src/composables/useDeliveryTracking.js`](ui/src/composables/useDeliveryTracking.js) |
| Vue API 클라이언트 | [`ui/src/api/client.js`](ui/src/api/client.js) |

---

## 5. 실행

### 5.1 전제

| 도구 | 버전 |
| --- | --- |
| JDK | 17 |
| Maven | 3.8+ |
| Node.js | 20+ |

### 5.2 백엔드 — 빌드와 테스트

```bash
cd 드론배달/개발/services
mvn test
```

특정 서비스만:

```bash
mvn -pl delivery -am test
```

### 5.3 백엔드 — 로컬 실행

```bash
mvn -pl delivery -am spring-boot:run
```

> ⚠️ 로컬 실행에는 Redis 등 의존 자원이 필요합니다. 의존성 없이 «기동만» 확인하려면
> `package-service` 와 `delivery-history` 를 쓰세요 — 메모리 구현이 기본값입니다.

### 5.4 프런트엔드

```bash
cd 드론배달/개발/ui
npm install
npm test          # Vitest 12개
npm run lint      # ESLint
npm run build     # 프로덕션 번들
npm run dev       # 개발 서버 (http://localhost:5173)
```

### 5.5 컨테이너 이미지

빌드 컨텍스트는 각 서비스 폴더가 아니라 **`services/`** 입니다 — 멀티모듈이라 부모 POM 이 필요합니다.

```bash
cd 드론배달/개발/services
docker build -f delivery/Dockerfile -t acrdronedevkrc.azurecr.io/delivery:$(git rev-parse --short HEAD) .
```

> ⛔ `latest` 태그를 쓰지 않습니다 (SEC‑10). 태그는 커밋 SHA 로 고정합니다.

---

## 6. API 문서 (Swagger)

각 서비스가 기동하면 자동으로 제공됩니다.

| 경로 | 내용 |
| --- | --- |
| `/swagger-ui.html` | 대화형 문서 |
| `/v3/api-docs` | OpenAPI 3.1 JSON |

> ⛔ **운영(prd)에서는 비활성**입니다 (`SWAGGER_ENABLED=false`). API 구조를 공개하지 않습니다.

---

## 7. 구성 — 비밀이 없는 상태

```yaml
spring:
  cloud:
    azure:
      credential:
        managed-identity-enabled: true      # ★ 비밀 없음
        client-id: ${AZURE_CLIENT_ID}       # 앱별 사용자 할당 관리 ID
      cosmos:
        endpoint: ${COSMOS_ENDPOINT}
        # key 없음 — 데이터 평면 RBAC 으로 접근
```

| 환경 변수 | 용도 | 비밀인가 |
| --- | --- | :---: |
| `AZURE_CLIENT_ID` | 어느 관리 ID 를 쓸지 | ❌ 공개 식별자 |
| `SERVICEBUS_NAMESPACE` · `EVENTHUB_NAMESPACE` | 엔드포인트 이름 | ❌ |
| `COSMOS_ENDPOINT` · `REDIS_HOST` · `STORAGE_ACCOUNT` | 엔드포인트 주소 | ❌ |
| `KEYVAULT_ENDPOINT` | 2순위 경로용 | ❌ |
| **연결 문자열 · 계정 키 · 비밀번호** | — | **주입하지 않음** |

Terraform 이 이 값들을 앱에 주입합니다 → [`구축/terraform/envs/*/main.tf`](../구축/terraform/) 의
`common_environment_variables`.

---

## 8. 아직 «실제 연결»되지 않은 지점

> 본 과제는 **실제 실행·배포를 하지 않는 것**이 전제입니다(CON‑06).
> 그래서 외부 자원을 실제로 호출하는 어댑터는 «로그 구현»을 기본값으로 두었습니다.
> 숨기지 않고 명시합니다.

| 위치 | 현재 | 실제 배포 시 교체 대상 |
| --- | --- | --- |
| `DeliveryConfig#eventSender` | 로그 출력 | `EventHubsTemplate` 주입 |
| `DroneConfig#droneEventPublisher` | 로그 출력 | 동일 |
| `IngestionConfig#queuePublisher` | 로그 출력 | `ServiceBusSenderClient` 주입 |
| `DeliveryRequestConsumer` | 호출 진입점만 | `@ServiceBusListener` 연결 |
| `PackageConfig` 저장소 | 메모리 | Cosmos DB for MongoDB 구현 |
| `HistoryConfig` 저장소 | 메모리 | Cosmos DB + Data Lake 구현 |
| `HistoryConfig#processedEventStore` | 메모리 Set | **Redis `SET NX EX`** — 인스턴스가 여럿이면 메모리로는 중복이 안 걸러진다 |

각 위치에 «왜 이렇게 두었고 무엇으로 바꿔야 하는지»가 주석으로 적혀 있습니다.

---

## 9. 설계 문서와의 대응

| 이 폴더의 구현 | 근거 설계서 |
| --- | --- |
| 애그리거트 · 값 개체 · 도메인 이벤트 | [분석/04 전술적 DDD](../분석/04_전술적_DDD_모델링.md) |
| 서비스 분리 · 책임 경계 | [분석/05 마이크로서비스 경계](../분석/05_마이크로서비스_경계_식별.md) |
| Spring Apps 선택 | [설계/02 컴퓨팅 플랫폼](../설계/02_컴퓨팅_플랫폼_선정서.md) |
| 재시도·회로차단·격벽 수치 | [설계/03 서비스 간 통신](../설계/03_서비스간_통신_설계서.md) §4 |
| REST 규약 · 멱등성 · 상태 코드 | [설계/04 API 설계서](../설계/04_API_설계서.md) |
| 저장소 선택 · Saga 보상 | [설계/06 데이터 설계서](../설계/06_데이터_설계서.md) |
| 22개 패턴 적용 위치 | [설계/07 디자인 패턴](../설계/07_디자인패턴_적용_설계서.md) |
| 관리 ID · 비밀 없는 접근 | [설계/09 보안·아이덴티티](../설계/09_보안_아이덴티티_설계서.md) |
| 메트릭 · 로그 · 추적 | [설계/10 관측성](../설계/10_관측성_설계서.md) |
