# 04. API 설계서

> **목적** — 「API 디자인」의 규칙에 따라 **공개 API 와 백엔드 API 를 구분**하고,
> DDD 모델을 REST 리소스로 변환하며, 버전 관리·멱등성 규약을 확정합니다.
> 앞: [03_서비스간_통신_설계서.md](03_서비스간_통신_설계서.md) · 다음: [05_API_게이트웨이_설계서.md](05_API_게이트웨이_설계서.md)

---

## 1. 공개 API vs 백엔드 API

| | **공개 API** | **백엔드(내부) API** |
| --- | --- | --- |
| 소비자 | Vue UI · 드론 · 외부 파트너 | 다른 마이크로서비스 |
| 우선 가치 | **상호 운용성 · 안정성 · 문서화** | **성능 · 진화 속도** |
| 프로토콜 | HTTPS / REST / JSON | HTTP / REST / JSON (내부망) |
| 버전 정책 | **엄격** — 하위 호환 필수, 폐기 예고 기간 필요 | 유연 — 소비자와 협의 후 변경 가능 |
| 인증 | Entra ID (OAuth 2.0 Bearer) | 워크로드 ID + 네트워크 격리 |
| 문서 | **Swagger UI 공개** | Swagger UI (내부만) |
| 이 시스템 | Ingestion · Delivery · Delivery History · Drone Scheduler(텔레메트리) | Package · Account · Delivery(내부 PUT) |

---

## 2. DDD → REST 매핑 규칙

> 「API 디자인」 문서의 매핑 표를 그대로 적용합니다.

| DDD 개념 | REST 표현 | 이 시스템의 예 |
| --- | --- | --- |
| **애그리거트** | 리소스 | `Delivery` → `/api/deliveries/{id}` |
| **아이덴티티** | URL 경로 | `deliveryId` → `/api/deliveries/dlv-0001` |
| **하위 엔터티** | 링크 또는 하위 리소스 | `Confirmation` → `/api/deliveries/{id}/confirmation` |
| **값 개체 업데이트** | `PUT` / `PATCH` | `Eta` 갱신 → `PATCH /api/deliveries/{id}` |
| **리포지토리** | 컬렉션 | `/api/deliveries?accountId=...` |
| **도메인 이벤트** | (REST 아님) | Event Hubs 로 발행 |
| **커맨드(부작용)** | 리소스 상태 전이 또는 하위 리소스 생성 | 취소 → `DELETE /api/deliveries/{id}` |

### 2.1 ❌ RPC 스타일을 피한다

```
❌ 동사 중심 (RPC 냄새)                    ✅ 리소스 중심
────────────────────────                  ────────────────────────
POST /api/createDelivery                   POST   /api/deliveries
POST /api/cancelDelivery?id=1              DELETE /api/deliveries/dlv-0001
POST /api/assignDrone                      PUT    /api/drones/assignments/dlv-0001
GET  /api/getDeliveryStatus?id=1           GET    /api/deliveries/dlv-0001/status
```

> ⚠️ **예외를 인정하는 경우** — 도메인에 정말 «행위»가 존재할 때는 하위 리소스로 표현합니다.
> 예: 배달 재조정 → `POST /api/deliveries/{id}/reschedules` (재조정 «기록»을 생성한다)

---

## 3. API 카탈로그

### 3.1 Ingestion (공개)

| 메서드 | 경로 | 설명 | 응답 |
| --- | --- | --- | --- |
| `POST` | `/api/v1/deliveries` | 배달 예약 요청 접수 | `202 Accepted` + `Location` |
| `DELETE` | `/api/v1/deliveries/{id}` | 예약 취소 요청 접수 | `202 Accepted` |
| `GET` | `/actuator/health` | 상태 프로브 | `200` |

**`POST /api/v1/deliveries` 요청**

```json
{
  "ownerId": "acc-0001",
  "pickup":  { "latitude": 37.5665, "longitude": 126.9780, "altitude": 0 },
  "dropoff": { "latitude": 37.5172, "longitude": 127.0473, "altitude": 0 },
  "pickupWindow": { "earliest": "2026-08-29T10:00:00Z", "latest": "2026-08-29T11:00:00Z" },
  "package": { "weight": { "value": 2.5, "unit": "KG" }, "size": "SMALL", "description": "서류 봉투" },
  "contact": { "name": "홍길동", "phone": "010-****-1234" }
}
```

**응답 `202 Accepted`**

```json
{
  "deliveryId": "dlv-7f3a9c",
  "status": "PENDING",
  "statusUrl": "/api/v1/deliveries/dlv-7f3a9c/status",
  "correlationId": "req-abc123"
}
```
```
Location: /api/v1/deliveries/dlv-7f3a9c
Retry-After: 2
```

> **왜 `201 Created` 가 아니라 `202 Accepted` 인가** — 요청을 **접수**했을 뿐 배달이 아직 생성되지 않았습니다.
> `201` 을 반환하면 클라이언트는 «만들어졌다»고 믿고 즉시 조회했다가 404 를 받습니다.
> `202` + `Location` + `Retry-After` 는 **비동기 요청‑회신 패턴**의 표준 표현입니다.

### 3.2 Delivery (공개 조회 + 내부 쓰기)

| 메서드 | 경로 | 유형 | 설명 |
| --- | --- | --- | --- |
| `GET` | `/api/v1/deliveries/{id}` | 공개 | 배달 상세 |
| `GET` | `/api/v1/deliveries/{id}/status` | 공개 | **상태·위치·ETA (추적 화면 전용, 경량)** |
| `PUT` | `/api/v1/deliveries/{id}` | 내부 | 배달 생성·갱신 (**멱등**) |
| `PATCH` | `/api/v1/deliveries/{id}` | 내부 | 부분 갱신 (ETA 등) |
| `DELETE` | `/api/v1/deliveries/{id}` | 내부 | 취소 |
| `POST` | `/api/v1/deliveries/{id}/confirmation` | 내부 | 수령 확인 기록 |

**`GET /api/v1/deliveries/{id}/status` 응답** — NFR‑02 (p95 ≤ 150 ms) 를 위해 **최소 필드**만

```json
{
  "deliveryId": "dlv-7f3a9c",
  "status": "HEADED_TO_DROPOFF",
  "droneLocation": { "latitude": 37.5401, "longitude": 127.0102, "altitude": 85 },
  "eta": { "arrivalTime": "2026-08-29T10:42:00Z", "confidence": 0.87, "estimatedAt": "2026-08-29T10:31:12Z" },
  "updatedAt": "2026-08-29T10:31:12Z"
}
```

### 3.3 Package (내부)

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| `PUT` | `/api/v1/packages/{id}` | 패키지 등록·갱신 (**멱등**) |
| `GET` | `/api/v1/packages/{id}` | 조회 |
| `DELETE` | `/api/v1/packages/{id}` | 삭제 (보상 트랜잭션용) |

### 3.4 Drone Scheduler (공개 텔레메트리 + 내부 할당)

| 메서드 | 경로 | 유형 | 설명 |
| --- | --- | --- | --- |
| `PUT` | `/api/v1/drones/assignments/{deliveryId}` | 내부 | 드론 할당 (**멱등**) |
| `DELETE` | `/api/v1/drones/assignments/{deliveryId}` | 내부 | 할당 해제 (보상) |
| `POST` | `/api/v1/drones/{droneId}/telemetry` | 공개(드론) | 위치·배터리 보고 |
| `GET` | `/api/v1/drones/{droneId}` | 내부 | 드론 상태 |

**`PUT /api/v1/drones/assignments/{deliveryId}`**

```json
// 요청
{ "requiredCapacityKg": 2.5, "pickup": { "latitude": 37.5665, "longitude": 126.9780 } }

// 200 OK — 할당 성공
{ "deliveryId": "dlv-7f3a9c", "droneId": "drn-0042", "assignedAt": "2026-08-29T10:00:03Z" }

// 409 Conflict — 가용 드론 없음 (INV-03)
{ "type": "https://fabrikam.example/errors/no-available-drone",
  "title": "가용 드론 없음", "status": 409,
  "detail": "요청 용량 2.5kg 을 처리할 수 있는 드론이 없습니다.",
  "instance": "/api/v1/drones/assignments/dlv-7f3a9c" }
```

> **`PUT`(멱등) 을 쓴 이유** — 리소스 ID 가 `deliveryId` 이므로 «이 배달의 드론 할당»은 하나뿐입니다.
> 재시도로 같은 요청이 두 번 와도 결과가 같습니다. `POST /api/v1/drones/assign` 이었다면
> 재시도가 **드론 두 대를 할당**할 수 있습니다.

### 3.5 Delivery History (공개 조회)

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| `GET` | `/api/v1/history/{deliveryId}` | 배달 이력 상세 |
| `GET` | `/api/v1/history?accountId=&from=&to=&page=&size=` | 기간·계정별 목록 (페이징) |
| `GET` | `/api/v1/history/summary?accountId=&month=` | 월간 집계 |

### 3.6 Account (내부 · 모의)

| 메서드 | 경로 | 설명 |
| --- | --- | --- |
| `GET` | `/api/v1/accounts/{id}` | 계정 조회 |
| `GET` | `/api/v1/accounts/{id}/validity` | 예약 가능 여부 (경량) |

---

## 4. 멱등성 설계

> **원칙** — 재시도되는 모든 연산은 멱등이어야 합니다. ([03 통신 설계서](03_서비스간_통신_설계서.md) §4.1)

| 메서드 | 멱등? | 이 시스템에서의 사용 |
| --- | :---: | --- |
| `GET` | ✅ | 모든 조회 |
| `PUT` | ✅ | **생성·갱신에 우선 사용** |
| `DELETE` | ✅ | 취소·해제 (이미 없으면 `204`) |
| `PATCH` | ⚠️ | 절대 값 설정만 (증감 연산 금지) |
| `POST` | ❌ | **`Idempotency-Key` 헤더로 보완** |

### 4.1 `POST` 를 피할 수 없는 경우

`POST /api/v1/deliveries` (Ingestion) 는 클라이언트가 ID 를 모르므로 `POST` 입니다.

```http
POST /api/v1/deliveries
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
Content-Type: application/json
```

| 처리 | 동작 |
| --- | --- |
| 최초 요청 | 처리 후 `(키 → 응답)` 을 24시간 캐시 |
| 동일 키 재요청 (동일 본문) | **캐시된 응답을 그대로 반환** (재처리 안 함) |
| 동일 키 재요청 (다른 본문) | `422 Unprocessable Entity` |
| 키 없음 | `400 Bad Request` (공개 API 에서는 필수) |

### 4.2 `PATCH` 의 함정

```
❌ 비멱등 PATCH                        ✅ 멱등 PATCH
{ "etaDeltaMinutes": +5 }              { "eta": { "arrivalTime": "2026-08-29T10:42:00Z" } }
  → 재시도하면 +10 분                     → 재시도해도 같은 값
```

---

## 5. 동시성 제어

| 리소스 | 방식 | 구현 |
| --- | --- | --- |
| `Delivery` | 낙관적 — `ETag` / `If-Match` | Redis 의 버전 필드 |
| `Drone` | 낙관적 — Cosmos DB `_etag` | INV‑03 보장의 핵심 |
| `Package` | 낙관적 — 문서 버전 | |

```http
# 조회 시 ETag 를 받는다
GET /api/v1/deliveries/dlv-7f3a9c
200 OK
ETag: "7"

# 갱신 시 ETag 를 되돌려 준다
PATCH /api/v1/deliveries/dlv-7f3a9c
If-Match: "7"

# 그 사이 누가 바꿨으면
412 Precondition Failed
```

> **왜 비관적 잠금을 쓰지 않는가** — 분산 환경에서 잠금은 «잠금을 쥔 채 죽는» 문제가 있고,
> 잠금 서비스가 새로운 단일 실패 지점이 됩니다. 충돌 빈도가 낮은 이 도메인에서는 낙관적 제어가 적합합니다.

---

## 6. 오류 응답 규약 — RFC 9457 (Problem Details)

모든 서비스가 **동일한 오류 형식**을 씁니다.

```json
{
  "type":     "https://fabrikam.example/errors/invalid-state-transition",
  "title":    "허용되지 않는 상태 전이",
  "status":   409,
  "detail":   "IN_TRANSIT 상태의 배달은 취소할 수 없습니다.",
  "instance": "/api/v1/deliveries/dlv-7f3a9c",
  "correlationId": "req-abc123",
  "errors": [
    { "field": "status", "message": "현재 IN_TRANSIT" }
  ]
}
```
`Content-Type: application/problem+json`

### 6.1 상태 코드 규약

| 코드 | 사용 상황 | 이 시스템의 예 |
| --- | --- | --- |
| `200` | 조회·갱신 성공 | `GET /deliveries/{id}` |
| `201` | 리소스 생성 완료 | `POST /deliveries/{id}/confirmation` |
| `202` | **접수했으나 처리 미완료** | `POST /api/v1/deliveries` |
| `204` | 성공, 본문 없음 | `DELETE` |
| `400` | 요청 형식 오류 | 필수 필드 누락 |
| `401` | 인증 없음/실패 | 토큰 없음 |
| `403` | 권한 없음 | 타 계정의 배달 조회 |
| `404` | 리소스 없음 | 없는 `deliveryId` |
| `409` | **도메인 불변식 위반** | INV‑01 취소 불가 · INV‑03 드론 없음 |
| `412` | 낙관적 동시성 충돌 | `If-Match` 불일치 |
| `422` | 형식은 맞으나 처리 불가 | `Idempotency-Key` 본문 불일치 |
| `429` | 속도 제한 초과 | 게이트웨이가 반환 |
| `500` | 서버 내부 오류 | **도메인 정보 노출 금지** |
| `503` | 일시적 사용 불가 | 회로 차단기 열림 · `Retry-After` 포함 |

> ⚠️ **`409` 와 `400` 의 구분** — «요청이 잘못됐다»(400)와 «요청은 맞지만 지금 상태에서 불가»(409)는 다릅니다.
> 클라이언트가 재시도해야 할지 판단하는 근거가 되므로 정확히 구분합니다.

---

## 7. 버전 관리

### 7.1 규칙

| 항목 | 정책 |
| --- | --- |
| 버전 위치 | **URL 경로** — `/api/v1/...` |
| 버전 형식 | **주(Major) 버전만** — `v1`, `v2`. 부(minor)·수정(patch)은 URL 에 넣지 않음 |
| 하위 호환 변경 | 필드 **추가**, 선택 필드 추가, 새 엔드포인트 → **버전 유지** |
| 호환 파괴 변경 | 필드 **삭제**, 타입 변경, 의미 변경, 필수 필드 추가 → **새 주 버전** |
| 병행 운영 | 새 버전 출시 후 이전 버전 **최소 6개월** 유지 |
| 폐기 예고 | `Deprecation` · `Sunset` 응답 헤더 + 문서 공지 |

```
   왜 주 버전만 URL 에 넣는가?
   ─────────────────────────
   /api/v1.2.3/deliveries   ← ❌ 패치마다 클라이언트가 URL 을 바꿔야 함
   /api/v1/deliveries       ← ✅ 하위 호환 변경은 클라이언트에 투명
```

### 7.2 이벤트 스키마 버전

REST 와 별개로 이벤트에도 버전이 있습니다. ([분석/04](../분석/04_전술적_DDD_모델링.md) §5.3)

| 변경 | 허용 | 조치 |
| --- | :---: | --- |
| 선택 필드 추가 | ✅ | `eventVersion` 유지 (소비자가 무시) |
| 필수 필드 추가 | ❌ | `eventVersion` 증가 + 병행 발행 |
| 필드 삭제 | ❌ | 동일 |
| 필드 의미 변경 | ❌ | **가장 위험** — 새 필드 추가 후 이전 필드 폐기 |

---

## 8. OpenAPI (Swagger) 규약

### 8.1 문서 생성

```xml
<!-- pom.xml -->
<dependency>
  <groupId>org.springdoc</groupId>
  <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
  <version>2.6.0</version>
</dependency>
```

| 엔드포인트 | 내용 | 노출 |
| --- | --- | --- |
| `/v3/api-docs` | OpenAPI 3.1 JSON | 내부만 |
| `/swagger-ui.html` | 대화형 문서 | dev·stg **only** (prd 는 차단) |

### 8.2 필수 어노테이션 규약

```java
@Tag(name = "Deliveries", description = "배달 예약 · 추적")
@RestController
@RequestMapping("/api/v1/deliveries")
public class DeliveryController {

    @Operation(summary = "배달 상태 조회",
               description = "추적 화면 전용 경량 응답. p95 150ms 목표.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "조회 성공",
            content = @Content(schema = @Schema(implementation = DeliveryStatusResponse.class))),
        @ApiResponse(responseCode = "404", description = "배달 없음",
            content = @Content(schema = @Schema(implementation = ProblemDetail.class)))
    })
    @GetMapping("/{id}/status")
    public DeliveryStatusResponse getStatus(
        @Parameter(description = "배달 ID", example = "dlv-7f3a9c")
        @PathVariable String id) { ... }
}
```

| 규약 | 강제 방법 |
| --- | --- |
| 모든 컨트롤러에 `@Tag` | 정적 검증 |
| 모든 엔드포인트에 `@Operation(summary=...)` | 정적 검증 |
| 모든 오류 응답에 `ProblemDetail` 스키마 | 정적 검증 |
| 모든 `@Parameter` 에 `example` | 코드 리뷰 |

### 8.3 계약을 코드보다 먼저 (Contract‑First)

```
   공통/openapi/*.yaml  ← ★ 진실의 원천 (SDD 의 spec 에 해당)
        │
        ├──▶ 서버: 계약 테스트가 실제 응답과 대조
        ├──▶ 클라이언트(Vue): 타입 생성
        └──▶ 문서: Swagger UI
```

> 코드에서 생성한 OpenAPI 와 `공통/openapi/` 의 계약이 **다르면 빌드를 실패**시킵니다.
> → [테스트/integration](../테스트/) 의 계약 테스트

---

## 9. API 보안

| 항목 | 공개 API | 내부 API |
| --- | --- | --- |
| 인증 | Entra ID OAuth 2.0 Bearer 토큰 | 워크로드 ID + 네트워크 격리 |
| 권한 | 계정 소유자만 자기 배달 조회 | 서비스 ID 기반 |
| 속도 제한 | 게이트웨이에서 (계정당 100 req/min) | 없음 (Bulkhead 로 대체) |
| 입력 검증 | Bean Validation + 게이트웨이 WAF | Bean Validation |
| 출력 | **개인정보 마스킹** (전화번호 등) | 동일 |
| CORS | Vue UI 오리진만 허용 | 비활성 |

```java
// 소유권 검증 — 다른 계정의 배달을 볼 수 없다 (403)
@PreAuthorize("@deliveryOwnership.isOwner(#id, authentication)")
@GetMapping("/{id}")
public DeliveryResponse get(@PathVariable String id) { ... }
```

---

## 10. API 설계 체크리스트

- [x] 공개 API 와 내부 API 를 구분했다
- [x] DDD 개념을 리소스로 매핑했다 (동사 URL 없음)
- [x] 재시도되는 연산이 모두 멱등이다 (`PUT` 우선 · `POST` 는 `Idempotency-Key`)
- [x] 비동기 접수는 `202 Accepted` + `Location` + `Retry-After` 로 표현했다
- [x] 오류를 RFC 9457 Problem Details 로 통일했다
- [x] `400` / `409` / `412` 를 정확히 구분했다
- [x] 낙관적 동시성(`ETag`/`If-Match`)을 설계했다
- [x] 버전은 주 버전만 URL 에, 하위 호환 규칙을 명시했다
- [x] OpenAPI 를 계약(진실의 원천)으로 두고 계약 테스트로 강제한다
- [x] prd 에서 Swagger UI 를 차단한다
