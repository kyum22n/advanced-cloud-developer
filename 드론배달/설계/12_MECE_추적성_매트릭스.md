# 12. MECE 추적성 매트릭스

> **목적** — 요구사항 → 설계 → 코드 → 테스트가 **빠짐없이(CE) 겹치지 않게(ME)** 연결되어 있음을
> 한 표로 증명합니다. 이 문서가 «완료 판정»의 근거입니다.
> 앞: [11_SDD_명세주도개발_계획서.md](11_SDD_명세주도개발_계획서.md)

---

## 1. MECE 검증의 두 방향

```
   ① Collectively Exhaustive (빠짐없이)
      모든 요구사항이 최소 하나의 설계·코드·테스트에 연결되는가?
      → 연결 없는 요구사항 = «구현되지 않은 요구사항»

   ② Mutually Exclusive (겹치지 않게)
      하나의 책임이 두 곳에 구현되어 있지 않은가?
      → 중복 구현 = «둘 중 하나만 고쳐서 생기는 버그»
```

---

## 2. 기능 요구사항 추적 (FR 23건)

| FR | 요구사항 | 설계 | 서비스 | 코드 | 테스트 |
| --- | --- | --- | --- | --- | --- |
| A‑01 | 기업 계정 등록 | 분석/02 §4 (일반) | Account 🧪 | `AccountController` | 통합 `account.ps1` |
| A‑02 | 사용자 추가·삭제 | 동일 | Account 🧪 | 동일 | 동일 |
| A‑03 | 계정 상태로 예약 차단 | 설계/06 §5 Saga ① | Account · Workflow | `SchedulerService#validateAccount` | 통합 `saga-account-blocked` |
| A‑04 | 청구 내역 조회 | 분석/02 §4 (지원) | — (범위 밖) | — | — |
| B‑01 | 배달 예약 | 설계/04 §3.1 | Ingestion | `IngestionController#create` | 단위 + E2E `AC-1` |
| B‑02 | 패키지 정보 제출 | 설계/04 §3.3 | Package | `PackageController#upsert` | 단위 |
| B‑03 | 즉시 배달 ID 반환 | 설계/07 §3.1 큐 부하 평준화 | Ingestion | `IngestionController` `202` | E2E `AC-1` (p95) |
| B‑04 | 드론 자동 할당 | 설계/06 §3.3 | Drone Scheduler | `DroneService#assign` | 단위 INV‑03 + 통합 |
| B‑05 | 타사 위탁 | 설계/07 §3.4 ACL | Workflow | `ThirdPartyTransportAdapter` | 통합 `AC-5` |
| B‑06 | 예약 취소 | 분석/03 INV‑01 | Delivery | `Delivery#cancel` | 단위 `AC-3` |
| B‑07 | 일정 변경 | 분석/03 §4 #11 | Delivery | `Delivery#reschedule` | 단위 |
| C‑01 | 드론 위치 보고 | 설계/04 §3.4 | Drone Scheduler | `DroneController#telemetry` | 통합 |
| C‑02 | 드론 위치 조회 | 설계/07 §3.5 CQRS | Delivery | `DeliveryController#getStatus` | E2E |
| C‑03 | ETA 재계산 | 분석/04 §6.1 | Delivery | `EtaCalculator` | 단위 |
| C‑04 | 상태 이벤트 발행 | 분석/04 §5 | Delivery | `EventPublisher` | 통합 |
| C‑05 | 수령 확인 기록 | 분석/04 §3.1 | Delivery | `Delivery#complete` | 단위 |
| C‑06 | 상태 변화 알림 | 분석/03 POL‑08 | Delivery | `NotificationService` | 통합 |
| D‑01 | 이력 적재 | 설계/06 §3.4 | Delivery History | `HistoryEventHandler` | 통합 |
| D‑02 | 이력 상세 조회 | 설계/04 §3.5 | Delivery History | `HistoryController#get` | E2E |
| D‑03 | 기간·계정 집계 | 설계/07 §3.6 구체화된 뷰 | Delivery History | `HistoryController#summary` | 통합 |
| E‑01 | 상태 프로브 | 설계/10 §9 | 전 서비스 | `HealthIndicator` | 스모크 |
| E‑02 | 자동 보상 | 설계/06 §5 Saga | Workflow | `SupervisorService` | 통합 `AC-6` |
| E‑03 | 지연·정체 경고 | 설계/10 §7 A‑03 | (경고 규칙) | Terraform `monitor` | 검증 스크립트 |

**CE 검증** — 23건 중 22건 연결 · 1건(A‑04 청구)은 **의도적으로 범위 밖**([분석/06](../분석/06_아키텍처_스타일_비교.md) ADR‑003)

---

## 3. 비기능 요구사항 추적 (NFR 12건 → WAF 35항목)

| NFR | 목표 | 설계 대응 | 구현 위치 | 검증 |
| --- | --- | --- | --- | --- |
| 01 | 예약 p95 ≤ 300 ms | 큐 부하 평준화 | `IngestionController` `202` | 부하 테스트 |
| 02 | 추적 p95 ≤ 150 ms | CQRS + Redis 읽기 모델 | `delivery:status:*` | 부하 테스트 |
| 03 | 500 req/s | 큐 + 경쟁 소비자 + HPA | Terraform `springapps` 자동 확장 | 부하 테스트 |
| 04 | 10,000 msg/s | Event Hubs 16 파티션 | Terraform `messaging` | 부하 테스트 |
| 05 | 가용성 99.9 % | 영역 중복 + 최소 2 인스턴스 | Terraform `envs/prd` | 가용성 계산 + 합성 모니터링 |
| 06 | 연쇄 실패 격리 | 회로 차단기 + Bulkhead | `resilience4j` 구성 | 카오스 시나리오 |
| 07 | 최종 일관성 ≤ 5초 | 이벤트 전파 | Event Hubs 구독 | 통합 테스트 |
| 08 | 평문 비밀 0 | 관리 ID | `spring.cloud.azure.credential` | 정적 검증 SEC‑V‑01 |
| 09 | 기본 거부 정책 | NSG 4096 거부 | Terraform `network` | 검증 SEC‑V‑11 |
| 10 | 추적 100 % | `correlationId` 전파 | MDC 필터 + 메시지 속성 | 통합 테스트 |
| 11 | 무중단 배포 | 블루‑그린 | Spring Apps 배포 슬롯 | 배포 검증 |
| 12 | 유휴 비용 ≤ 40 % | 자동 확장 하한 | Terraform 변수 | 비용 분석 |

---

## 4. 도메인 불변식 추적 (INV 6건)

| INV | 불변식 | 애그리거트 | 메서드 | JUnit 테스트 |
| --- | --- | --- | --- | --- |
| 01 | `InTransit` 이후 취소 불가 | Delivery | `cancel()` | `cancelAfterInTransitThrows` |
| 02 | 드론 없이 `InTransit` 불가 | Delivery | `markInTransit()` | `markInTransitWithoutDroneThrows` |
| 03 | 드론 1대 = 배달 1건 | Drone | `assign()` | `assignBusyDroneThrows` · `concurrentAssignOnlyOneWins` |
| 04 | 종료 상태에서 전이 불가 | Delivery | 전 전이 메서드 | `terminalStateRejectsAllTransitions` |
| 05 | 패키지 참조 필수 | Delivery | `create()` | `createWithoutPackageThrows` |
| 06 | ETA 는 미래 | Delivery | `updateEta()` | `pastEtaRejected` |

**ME 검증** — 각 불변식이 **정확히 하나의 애그리거트 메서드**에만 구현됨.
컨트롤러·서비스 계층에 중복 검사 없음(중복 검사는 «둘 중 하나만 고치는» 버그의 원인).

---

## 5. 패턴 → 코드 추적 (22개 패턴)

| 패턴 | 구현 위치 | 검증 |
| --- | --- | --- |
| 게이트웨이 라우팅 | Terraform `gateway` 경로 규칙 | 검증 스크립트 |
| 게이트웨이 오프로딩 | Terraform `gateway` WAF·TLS | SEC 검증 |
| 속도 제한 | Terraform `gateway` 사용자 지정 규칙 | 통합 테스트 |
| 큐 기반 부하 평준화 | `IngestionService#enqueue` | E2E p95 |
| 비동기 요청‑회신 | `202` + `statusUrl` | E2E |
| 경쟁 소비자 | `@ServiceBusListener` 다중 인스턴스 | 통합 |
| 게시자‑구독자 | `EventPublisher` / `@EventHubsListener` | 통합 |
| 멱등 소비자 | `IdempotencyGuard` (Redis SETNX) | 단위 + 통합 |
| 스케줄러 에이전트 감독자 | `SchedulerService` + `*Agent` + `SupervisorService` | 통합 `AC-6` |
| Saga | `SchedulerService#execute` | 통합 |
| 보상 거래 | 각 서비스 `DELETE` + `SchedulerService#compensate` | 통합 |
| 재시도 | `@Retry` | 단위 (오류 주입) |
| 회로 차단기 | `@CircuitBreaker` | 단위 |
| Bulkhead | `@Bulkhead` | 단위 |
| 손상 방지 계층 | `ThirdPartyTransportAdapter` | 정적 검증(외부 용어 누출 0) |
| CQRS | Ingestion(쓰기) / Delivery(읽기) | 아키텍처 검증 |
| 구체화된 뷰 | `delivery:status:*` · `drone:available` | 통합 |
| Cache‑Aside | `AccountCache` | 단위 |
| 상태 엔드포인트 모니터링 | `*HealthIndicator` | 스모크 |
| 외부 구성 저장소 | Spring Cloud Config Server | 배포 검증 |
| 페더레이션 ID | `managed-identity-enabled` | SEC‑V‑02 |
| 정적 콘텐츠 호스팅 | Terraform Storage 정적 웹사이트 | 검증 스크립트 |

---

## 6. 참조 지침 → 산출물 추적 (16종)

| # | 참조 문서 | 적용 산출물 | 구체적으로 무엇을 가져왔나 |
| --- | --- | --- | --- |
| 1 | 도메인 분석으로 마이크로서비스 모델링 | 분석/02 | 서브도메인 분류(핵심/지원/일반) · 컨텍스트 맵 패턴 |
| 2 | 전술 DDD | 분석/03, 04 | 애그리거트 3원칙 · Scheduler/Supervisor 도메인 서비스 |
| 3 | 마이크로서비스 경계 식별 | 분석/05 | «애그리거트 = 후보 → 비기능으로 조정» 절차 · Ingestion·History 추가 |
| 4 | 마이크로서비스 아키텍처 디자인 | 설계/01 | 논리·물리 아키텍처 구성 |
| 5 | 컴퓨팅 옵션 선택 | 설계/02 | 12개 기능 비교 항목 · 선택 지침 |
| 6 | 서비스 간 통신 | 설계/03 | 동기/비동기 결정 · 재시도·회로 차단기 |
| 7 | API 디자인 | 설계/04 | DDD→REST 매핑 표 · 멱등성 · 주 버전만 URL |
| 8 | API 게이트웨이 | 설계/05 | 라우팅·집계·오프로딩 3역할 · 옵션 비교 |
| 9 | 데이터 고려 사항 | 설계/06 | 폴리글랏 · Redis/Cosmos/Data Lake 선택 근거 |
| 10 | 컨테이너 오케스트레이션 | 설계/02, 08 | 오케스트레이터 비교 · Container Apps/AKS/ACI |
| 11 | 마이크로서비스 디자인 패턴 | 설계/07 | 9개 주요 패턴 + 지원 패턴 |
| 12 | N 계층 애플리케이션 | 분석/06 | 스타일 비교의 기준선 |
| 13 | Web‑queue‑worker | 분석/06, 설계/01 | **하이브리드 골격의 근거** |
| 14 | 클라우드 디자인 패턴 카탈로그 | 설계/07 | 22개 적용 + 13개 «쓰지 않은 이유» |
| 15 | Spring Cloud Azure | 설계/03·06·09, 개발/ | 관리 ID 구성 · Stream 바인더 · 암호 없는 연결 |
| 16 | `azure-architecture.pdf` (고급 AKS 마이크로서비스, p.2611~) | 설계/01·08·09·10 | Fabrikam 워크플로 5단계 · 허브‑스포크 · 워크로드 ID · 자동 확장 · 관측성 |

---

## 7. 산출물 완결성 검증

| 요청 항목 | 산출물 | 상태 |
| --- | --- | --- |
| 분석 폴더 MD | `분석/01~07` (7편) | ✅ |
| 설계 폴더 MD | `설계/01~12` (12편) | ✅ |
| 개발 — 인프라 | `개발/` 서비스별 구성 + `구축/terraform` | ✅ |
| 개발 — Azure Spring Cloud 마이크로서비스 | `개발/services/` 6개 | ✅ |
| 개발 — JUnit 단위 테스트 | 각 서비스 `src/test/java` | ✅ |
| 개발 — Swagger | `springdoc` + `공통/openapi/` | ✅ |
| 개발 — Vue.js UI | `개발/ui/` | ✅ |
| 테스트 — 스크립트 기반 통합/E2E | `테스트/` | ✅ |
| 구축 — Terraform + 스크립트 | `구축/terraform`, `구축/scripts` | ✅ |
| **실제 실행하지 않음** | 모든 스크립트가 산출물. 자동 실행 없음 | ✅ |
| 단계별 실습 프롬프트 | `실습자료/4차시_드론배달_마이크로서비스_개발.md` | ✅ |

---

## 8. ME 검증 — 중복 책임 점검

| 잠재 중복 | 확인 | 판정 |
| --- | --- | --- |
| 불변식 검사가 애그리거트와 컨트롤러 양쪽에? | 컨트롤러는 **형식 검증(Bean Validation)** 만, 도메인 규칙은 애그리거트만 | ✅ 분리 |
| 재시도가 애플리케이션과 큐 양쪽에? | 애플리케이션 재시도 = 서비스 간 호출 / 큐 재전달 = 메시지 처리 실패 · **계층이 다름** | ✅ 분리 |
| 인증이 게이트웨이와 서비스 양쪽에? | 게이트웨이 = **토큰 유효성** / 서비스 = **소유권 권한** · 역할이 다름 | ✅ 분리 |
| 배달 상태가 Redis 와 Cosmos 양쪽에? | Redis = **진행 중(핫)** / Cosmos = **완료 후 이력** · 수명 주기가 다름 | ✅ 분리 |
| ETA 계산이 Delivery 와 ETA 분석 양쪽에? | 본 범위에서는 **Delivery 만**. ETA 분석 컨텍스트는 향후 분리 | ✅ 단일 |
| 로깅이 게이트웨이와 앱 양쪽에? | 게이트웨이 = 접근 로그 / 앱 = 도메인 로그 · **관점이 다름** | ✅ 분리 |
| 속도 제한과 Bulkhead 가 중복? | 속도 제한 = **클라이언트별 공정성** / Bulkhead = **시스템 자원 보호** | ✅ 분리 |

---

## 9. 미해결 · 의도적 제외 항목

> 숨기지 않고 명시합니다. «완료»의 정의에는 «하지 않기로 한 것»도 포함됩니다.

| 항목 | 상태 | 근거 |
| --- | --- | --- |
| 청구서 컨텍스트 (FR‑A‑04) | 범위 밖 | ADR‑003 — 지원 서브도메인, 최소 구현 |
| ETA 분석 컨텍스트 분리 | 범위 밖 | 본 과정에서는 단순 거리·속도 모델로 대체 |
| 드론 공유 · 비디오 감시 | 범위 밖 | 미래 서브도메인. 경계만 확보 |
| Supervisor 별도 배포 | 의도적 통합 | ADR‑002 — 부하 대비 운영 비용 |
| Cosmos Mongo 완전 암호 없는 연결 | 부분 | [설계/06](06_데이터_설계서.md) §8.3 — 지원 확인 후 전환 |
| 실제 드론 비행 제어 | 범위 밖 | 물리 시스템 |
| 다중 지역 능동‑능동 | 범위 밖 | 단일 지역 + 영역 중복으로 NFR‑05 충족 |
| 실제 Azure 배포 실행 | **의도적 미실행** | CON‑06 — 본 과제는 산출물 생성 |

---

## 10. 최종 판정

```
   ✅ Collectively Exhaustive
      · 기능 요구사항 23건 → 22건 구현 · 1건 명시적 범위 밖
      · 비기능 요구사항 12건 → 12건 설계·검증 연결
      · 불변식 6건 → 6건 코드·테스트 연결
      · 참조 지침 16종 → 16종 «무엇을 가져왔는지» 명시

   ✅ Mutually Exclusive
      · 중복 책임 7개 후보 점검 → 전부 «관점·계층·수명 주기가 다름»으로 분리 확인
      · 불변식은 애그리거트 메서드에만 존재 (중복 검사 없음)

   ✅ 결정의 추적성
      · ADR 9건 — 각각 맥락·결정·근거·결과·대안·되돌릴 조건 기록
      · «쓰지 않은 패턴» 13개 — 근거와 재검토 조건 기록
```
