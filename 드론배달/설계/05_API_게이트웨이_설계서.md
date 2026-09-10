# 05. API 게이트웨이 설계서

> **목적** — 「마이크로 서비스에 대한 API 게이트웨이」의 세 가지 역할(라우팅·집계·오프로딩)을
> 이 시스템에 배치하고, Azure 게이트웨이 옵션을 비교해 선택합니다.
> 앞: [04_API_설계서.md](04_API_설계서.md) · 다음: [06_데이터_설계서.md](06_데이터_설계서.md)

---

## 1. 왜 게이트웨이가 필요한가

```
❌ 게이트웨이 없음                          ✅ 게이트웨이 있음
─────────────────────                      ─────────────────────
Vue UI ──▶ ingestion.azure.../api/...       Vue UI ──▶ api.fabrikam.example
      ──▶ delivery.azure.../api/...                        │
      ──▶ history.azure.../api/...                    [게이트웨이]
      ──▶ drone.azure.../api/...                           │
                                                  ┌────────┼────────┐
문제:                                             ▼        ▼        ▼
· 클라이언트가 서비스 위치를 안다              Ingestion Delivery History
  → 서비스 분리/이동 시 클라이언트 수정
· 인증·TLS·로깅을 각 서비스가 중복 구현      효과:
· 서비스마다 공개 엔드포인트 = 공격 표면 증가  · 단일 엔드포인트
· CORS 를 각 서비스가 관리                    · 횡단 관심사 1곳에 집중
                                              · 내부 구조 은닉
```

---

## 2. 게이트웨이의 세 가지 역할

### 2.1 게이트웨이 라우팅 (Gateway Routing)

경로에 따라 요청을 올바른 백엔드로 보냅니다.

| 경로 | 대상 서비스 | 비고 |
| --- | --- | --- |
| `POST /api/v1/deliveries` | **Ingestion** | 쓰기 접수 |
| `DELETE /api/v1/deliveries/{id}` | **Ingestion** | 취소 접수 |
| `GET /api/v1/deliveries/{id}` | **Delivery** | 조회 |
| `GET /api/v1/deliveries/{id}/status` | **Delivery** | 추적 (고빈도) |
| `POST /api/v1/drones/{id}/telemetry` | **Drone Scheduler** | 드론 전용 |
| `GET /api/v1/history/**` | **Delivery History** | 이력 조회 |
| `GET /` , `/assets/**` | **정적 콘텐츠 (Storage/Front Door)** | Vue SPA |

> ❗ **같은 `/api/v1/deliveries` 경로가 메서드에 따라 다른 서비스로 갑니다.**
> 쓰기는 Ingestion(큐 적재), 읽기는 Delivery(Redis 조회) — **CQRS 가 게이트웨이 라우팅으로 드러납니다.**

```
   POST   /api/v1/deliveries      ──▶ Ingestion  ──▶ Service Bus  (명령)
   GET    /api/v1/deliveries/{id} ──▶ Delivery   ──▶ Redis        (조회)
                                       ▲
                            클라이언트는 이 분리를 모른다
```

### 2.2 게이트웨이 집계 (Gateway Aggregation)

여러 백엔드 호출을 하나로 합쳐 왕복을 줄입니다.

| 화면 | 필요한 데이터 | 집계 여부 | 판단 |
| --- | --- | --- | --- |
| 추적 화면 | 배달 상태 + 드론 위치 + ETA | ❌ **집계 안 함** | Delivery 가 이미 **읽기 모델에 비정규화**해 한 번에 반환. 게이트웨이 집계는 불필요 |
| 배달 상세 | 배달 + 패키지 + 이력 | ⚠️ **BFF 에서 집계** | 게이트웨이가 아니라 **Backends for Frontends** 계층에서 |
| 월간 리포트 | 이력 집계 + 계정 | ❌ | Delivery History 가 자체 집계 |

> 🔑 **결정 — 게이트웨이에서 집계하지 않습니다.**
> 이유: ① 집계 로직이 게이트웨이에 들어가면 게이트웨이가 «도메인을 아는» 상태가 되어 결합이 생김
> ② Azure Application Gateway 는 집계 기능이 없음 ③ 읽기 모델 비정규화로 대부분 해결됨
>
> **되돌릴 조건** — 모바일 앱 등 «왕복 비용이 비싼 클라이언트»가 추가되면 **BFF 서비스**를 추가합니다.
> (게이트웨이 확장이 아니라 **별도 서비스**로 — [07 패턴 설계서](07_디자인패턴_적용_설계서.md) §BFF)

### 2.3 게이트웨이 오프로딩 (Gateway Offloading)

각 서비스가 중복 구현할 필요 없는 횡단 관심사를 게이트웨이로 옮깁니다.

| 관심사 | 게이트웨이에서 | 서비스에서 | 근거 |
| --- | :---: | :---: | --- |
| **TLS 종료** | ✅ | ✅ (재암호화) | 종단 간 암호화 (SEC‑07) |
| **WAF (OWASP)** | ✅ | ❌ | SQL 주입·XSS 등 공통 위협 |
| **인증 (토큰 검증)** | ✅ | ⚠️ 재검증 | 게이트웨이가 1차, 서비스가 최종 권한 판단 |
| **권한 (소유권 검증)** | ❌ | ✅ | **도메인 지식 필요** — 게이트웨이가 알면 안 됨 |
| **속도 제한** | ✅ | ❌ | 계정당 100 req/min |
| **IP 제한** | ✅ | ❌ | |
| **CORS** | ✅ | ❌ | |
| **요청/응답 로깅** | ✅ | ✅ | 게이트웨이는 접근 로그, 서비스는 도메인 로그 |
| **상관 ID 생성** | ✅ | ❌ | 없으면 게이트웨이가 생성 |
| **압축** | ✅ | ❌ | |
| **정적 콘텐츠** | ✅ | ❌ | Front Door/Storage |
| **입력 형식 검증** | ⚠️ WAF 수준 | ✅ Bean Validation | 도메인 규칙은 서비스가 |

> ⚠️ **오프로딩의 한계** — «도메인 지식이 필요한 것»은 절대 게이트웨이로 옮기지 않습니다.
> 소유권 검증(«이 사용자가 이 배달의 주인인가»)을 게이트웨이가 하려면 게이트웨이가 배달 데이터를
> 읽어야 하고, 그 순간 게이트웨이는 **또 하나의 서비스**가 됩니다.

---

## 3. Azure 게이트웨이 옵션 비교

| 옵션 | L7 라우팅 | 부하 분산 | WAF | 속도 제한 | 전역 | API 관리 기능 | 비용 |
| --- | :---: | :---: | :---: | :---: | :---: | :---: | --- |
| **역방향 프록시** (Nginx/HAProxy) | ✅ | ✅ | ⚠️ 직접 | ✅ | ❌ | ❌ | 낮음 (직접 운영) |
| **서비스 메시 인그레스** (Istio) | ✅ | ✅ | ❌ | ✅ | ❌ | ❌ | 운영 부담 |
| **Application Gateway** | ✅ | ✅ | ✅ **WAF v2** | ⚠️ 제한적 | ❌ (지역) | ❌ | 중간 |
| **Front Door** | ✅ | ✅ | ✅ | ✅ | ✅ **전역** | ❌ | 중간 |
| **API Management** | ✅ | ❌ **부하 분산 없음** | ❌ | ✅ | ⚠️ | ✅ **매우 강력** | 높음 |

### 3.1 선택

| 환경 | 구성 | 이유 |
| --- | --- | --- |
| **dev** | Spring Apps 기본 엔드포인트만 | 비용·단순성. WAF 불필요 |
| **stg** | **Application Gateway (WAF 감지 모드)** | prd 구성 검증. 차단하지 않고 로그만 |
| **prd** | **Front Door + Application Gateway (WAF 차단 모드)** | 전역 진입 + 지역 L7 + WAF |

```
   prd 게이트웨이 체인
   ───────────────────
   인터넷 ──▶ Front Door ──▶ Application Gateway ──▶ Spring Apps 인그레스 ──▶ 앱
              (전역 · CDN)     (지역 L7 · WAF v2)      (내부 라우팅)
                  │                   │
             정적 콘텐츠 캐시      OWASP 3.2 규칙 집합
             DDoS 보호           TLS 종료 + 재암호화
```

### 3.2 API Management 를 쓰지 않은 이유

| APIM 의 강점 | 이 시스템에서 필요한가 |
| --- | --- |
| 개발자 포털 · API 구독 키 | ❌ 외부 파트너 API 프로그램이 없음 |
| 정책 기반 변환 (XML↔JSON 등) | ❌ 전부 JSON |
| 사용량 기반 과금 · 할당량 | ❌ |
| API 버전·개정 관리 | ⚠️ URL 버전으로 충분 |
| **부하 분산** | ❌ **APIM 은 제공하지 않음** — App Gateway 와 함께 써야 함 |
| 비용 | 🔴 개발자 계층 외에는 상당한 고정 비용 |

> **되돌릴 조건** — 외부 파트너에게 API 를 상품으로 제공하게 되면 APIM 을 **App Gateway 뒤에** 추가합니다.
> (APIM 단독으로는 부하 분산이 안 되므로 반드시 짝을 이룹니다.)

---

## 4. Application Gateway 구성 설계 (prd)

### 4.1 리스너 · 규칙

| 리스너 | 프로토콜 | 포트 | 호스트 | 인증서 |
| --- | --- | --- | --- | --- |
| `https-api` | HTTPS | 443 | `api.fabrikam.example` | Key Vault 참조 |
| `http-redirect` | HTTP | 80 | * | — (301 → HTTPS) |

| 경로 기반 규칙 | 백엔드 풀 | 상태 프로브 |
| --- | --- | --- |
| `/api/v1/deliveries` (POST/DELETE) | `pool-ingestion` | `/actuator/health/readiness` |
| `/api/v1/deliveries/*` (GET) | `pool-delivery` | 동일 |
| `/api/v1/drones/*/telemetry` | `pool-drone` | 동일 |
| `/api/v1/history/*` | `pool-history` | 동일 |
| `/*` (기본) | `pool-static` | `/` |

### 4.2 WAF 정책

| 항목 | 설정 |
| --- | --- |
| 규칙 집합 | OWASP CRS 3.2 |
| 모드 | **차단(Prevention)** — stg 는 감지(Detection) |
| 요청 본문 검사 | ✅ 최대 128 KB |
| 파일 업로드 한도 | 100 MB |
| 사용자 지정 규칙 | ① 지역 차단(운영 대상국 외) ② `Idempotency-Key` 없는 `POST /api/v1/deliveries` 차단 |
| 제외 항목 | `contact.name` 필드 — 한글 이름이 CRS 규칙에 오탐되는 사례 대비 |

> ⚠️ **WAF 는 반드시 감지 모드로 먼저 운영합니다.** 바로 차단 모드로 켜면 정상 요청이 막혀
> 장애로 인식됩니다. stg 에서 최소 2주 로그를 관찰한 뒤 prd 를 차단 모드로 전환합니다.

### 4.3 종단 간 TLS

```
   클라이언트 ──TLS 1.2+──▶ Front Door ──TLS──▶ App Gateway ──TLS──▶ Spring Apps ──TLS──▶ 앱
                                                     │
                                          여기서 복호화(WAF 검사) 후
                                              백엔드로 재암호화
```

| 구간 | 인증서 | 최소 버전 |
| --- | --- | --- |
| 클라이언트 → Front Door | 공개 CA (`api.fabrikam.example`) | TLS 1.2 |
| Front Door → App Gateway | 공개 CA | TLS 1.2 |
| App Gateway → Spring Apps | Spring Apps 관리 인증서 | TLS 1.2 |

---

## 5. 속도 제한 설계

| 대상 | 한도 | 창 | 초과 시 |
| --- | --- | --- | --- |
| 계정당 배달 예약 | 100 req | 1분 | `429` + `Retry-After: 60` |
| 계정당 조회 | 1,000 req | 1분 | `429` |
| 드론당 텔레메트리 | 60 req | 1분 | `429` (드론이 로컬 버퍼링) |
| IP 당 전체 | 5,000 req | 1분 | `429` |
| 미인증 요청 | 10 req | 1분 | `429` |

> **속도 제한과 스로틀링의 차이** — 속도 제한은 «클라이언트별 공정성», 스로틀링은 «시스템 보호».
> 게이트웨이가 속도 제한을, 각 서비스의 Bulkhead 가 스로틀링을 담당합니다.

---

## 6. 게이트웨이 자체의 가용성

| 위험 | 대응 |
| --- | --- |
| 게이트웨이가 단일 실패 지점이 된다 | Application Gateway v2 **영역 중복 + 최소 2 인스턴스** |
| 게이트웨이가 병목이 된다 | 자동 확장 (용량 단위 2~10) |
| Front Door 지역 장애 | 다중 원본(origin) 구성 · 자동 장애 조치 |
| 인증서 만료 | **Key Vault 참조 + 자동 갱신** (수동 관리 금지) |

---

## 7. 정적 콘텐츠 (Vue SPA) 호스팅

```
   Front Door ──┬──▶ /api/**   ──▶ Application Gateway ──▶ Spring Apps
                └──▶ /**       ──▶ Storage 정적 웹사이트 (Vue 빌드 산출물)
                                    │
                                    └ CDN 캐시 (Front Door)
```

| 항목 | 설정 |
| --- | --- |
| 호스팅 | Storage 계정 정적 웹사이트 (`$web` 컨테이너) |
| 캐시 | `index.html` = no‑cache / `assets/*` = 1년 (파일명에 해시) |
| SPA 라우팅 | 404 → `index.html` 리라이트 |
| 접근 | Front Door 를 통해서만 (Private Link 또는 IP 제한) |

---

## 8. ADR‑006 · 게이트웨이 구성

| 항목 | 내용 |
| --- | --- |
| **상태** | 승인 |
| **결정** | prd = Front Door + Application Gateway(WAF v2 차단) / stg = App Gateway(감지) / dev = 없음. **게이트웨이 집계는 하지 않음.** APIM 미사용 |
| **근거** | §3 옵션 비교 · §2.2 집계 판단 · §3.2 APIM 판단 |
| **결과** | ➕ WAF·TLS·속도 제한을 1곳에 집중 · 내부 구조 은닉 ➖ 게이트웨이 계층 비용 · 지연 10~20 ms 추가 |
| **되돌릴 조건** | ① 왕복 비용이 큰 클라이언트 추가 → **BFF 서비스** 도입 ② 외부 파트너 API 상품화 → **APIM 추가** |

---

## 9. 체크리스트

- [x] 라우팅 규칙을 메서드·경로 단위로 정의했다
- [x] 집계를 게이트웨이에서 하지 않기로 하고 근거와 대안(BFF)을 명시했다
- [x] 오프로딩 항목과 «오프로딩하지 않을 것»(도메인 권한)을 구분했다
- [x] Azure 게이트웨이 5종을 비교하고 환경별로 선택했다
- [x] WAF 를 감지 → 차단 순서로 도입하도록 계획했다
- [x] 종단 간 TLS 구간을 명시했다
- [x] 속도 제한과 서비스 스로틀링의 역할을 나눴다
- [x] 게이트웨이 자체의 가용성을 설계했다
