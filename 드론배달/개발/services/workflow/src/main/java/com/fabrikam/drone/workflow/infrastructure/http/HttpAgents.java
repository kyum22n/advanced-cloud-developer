package com.fabrikam.drone.workflow.infrastructure.http;

import com.fabrikam.drone.contract.Headers;
import com.fabrikam.drone.contract.vo.*;
import com.fabrikam.drone.workflow.agent.*;
import io.github.resilience4j.bulkhead.annotation.Bulkhead;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;

/**
 * 내부 서비스 호출 에이전트 구현.
 *
 * <h2>복원력 어노테이션의 순서가 중요하다</h2>
 * <pre>
 *   &#64;Bulkhead        ← ① 동시 호출 수 제한 (가장 바깥)
 *   &#64;CircuitBreaker  ← ② 지속 실패 시 즉시 차단
 *   &#64;Retry           ← ③ 일시적 실패만 재시도 (가장 안쪽)
 * </pre>
 * 재시도가 회로 차단기 <b>바깥</b>에 있으면, 회로가 열려 있어도 재시도가 반복된다.
 * 회로 차단기가 바깥이어야 «열림 상태에서는 재시도조차 하지 않고 즉시 폴백»이 된다.
 */
public final class HttpAgents {

    private HttpAgents() {
    }

    // ─────────────────────────────────────────── 계정

    @Component
    public static class HttpAccountAgent implements AccountAgent {

        private static final Logger log = LoggerFactory.getLogger(HttpAccountAgent.class);
        private final RestClient client;

        public HttpAccountAgent(RestClient accountRestClient) {
            this.client = accountRestClient;
        }

        @Override
        @Bulkhead(name = "accountService")
        @CircuitBreaker(name = "accountService", fallbackMethod = "assumeActive")
        @Retry(name = "accountService")
        public boolean isActive(String accountId, String correlationId) {
            Map<?, ?> body = client.get()
                    .uri("/api/v1/accounts/{id}/validity", accountId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .retrieve()
                    .body(Map.class);
            return body != null && Boolean.TRUE.equals(body.get("active"));
        }

        /**
         * 폴백 — 계정 서비스가 죽었을 때 배달을 전부 거부하면 «가용성 없음»과 같다.
         * 계정 상태는 거의 바뀌지 않으므로 «활성»으로 가정하고 진행한다 (관대한 실패).
         * 이 결정은 사업적 판단이며, 부정 이용 위험을 감수하는 대신 가용성을 얻는다.
         */
        @SuppressWarnings("unused")
        private boolean assumeActive(String accountId, String correlationId, Throwable t) {
            log.warn("계정 서비스 사용 불가 — 활성으로 가정하고 진행합니다");
            return true;
        }
    }

    // ─────────────────────────────────────────── 패키지

    @Component
    public static class HttpPackageAgent implements PackageAgent {

        private final RestClient client;

        public HttpPackageAgent(RestClient packageRestClient) {
            this.client = packageRestClient;
        }

        @Override
        @Bulkhead(name = "packageService")
        @CircuitBreaker(name = "packageService")
        @Retry(name = "packageService")
        public String register(String packageId, PackageWeight weight, PackageSize size,
                               String description, String correlationId) {
            client.put()
                    .uri("/api/v1/packages/{id}", packageId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .body(Map.of(
                            "weightValue", weight == null ? BigDecimal.ONE : weight.value(),
                            "weightUnit", weight == null ? "KG" : weight.unit().name(),
                            "size", size == null ? PackageSize.SMALL.name() : size.name(),
                            "description", description == null ? "" : description))
                    .retrieve()
                    .toBodilessEntity();
            return packageId;
        }

        @Override
        @Bulkhead(name = "packageService")
        @Retry(name = "packageService")
        public void delete(String packageId, String correlationId) {
            client.delete()
                    .uri("/api/v1/packages/{id}", packageId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .retrieve()
                    // 보상은 멱등해야 한다 — 이미 없으면(404) 성공으로 본다.
                    .onStatus(HttpStatusCode::is4xxClientError, (req, res) -> { })
                    .toBodilessEntity();
        }
    }

    // ─────────────────────────────────────────── 드론

    @Component
    public static class HttpDroneAgent implements DroneAgent {

        private static final Logger log = LoggerFactory.getLogger(HttpDroneAgent.class);
        private final RestClient client;

        public HttpDroneAgent(RestClient droneRestClient) {
            this.client = droneRestClient;
        }

        @Override
        @Bulkhead(name = "droneService")
        @CircuitBreaker(name = "droneService", fallbackMethod = "noDrone")
        @Retry(name = "droneService")
        public Optional<String> assign(String deliveryId, BigDecimal requiredKg,
                                       String correlationId) {
            final boolean[] rejected = {false};
            Map<?, ?> body = client.put()
                    .uri("/api/v1/drones/assignments/{deliveryId}", deliveryId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .body(Map.of("requiredCapacityKg", requiredKg == null ? BigDecimal.ONE : requiredKg))
                    .retrieve()
                    // 409 «가용 드론 없음»은 오류가 아니라 «분기»다 — 예외로 만들지 않는다.
                    .onStatus(s -> s.value() == 409, (req, res) -> rejected[0] = true)
                    .body(Map.class);

            if (rejected[0] || body == null || body.get("droneId") == null) {
                return Optional.empty();
            }
            return Optional.of(String.valueOf(body.get("droneId")));
        }

        @SuppressWarnings("unused")
        private Optional<String> noDrone(String deliveryId, BigDecimal requiredKg,
                                         String correlationId, Throwable t) {
            log.warn("드론 서비스 사용 불가 — 타사 위탁으로 전환합니다");
            return Optional.empty();
        }

        @Override
        @Bulkhead(name = "droneService")
        @Retry(name = "droneService")
        public void release(String deliveryId, String correlationId) {
            client.delete()
                    .uri("/api/v1/drones/assignments/{deliveryId}", deliveryId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .retrieve()
                    .onStatus(HttpStatusCode::is4xxClientError, (req, res) -> { })
                    .toBodilessEntity();
        }
    }

    // ─────────────────────────────────────────── 배달

    @Component
    public static class HttpDeliveryAgent implements DeliveryAgent {

        private final RestClient client;

        public HttpDeliveryAgent(RestClient deliveryRestClient) {
            this.client = deliveryRestClient;
        }

        @Override
        @Bulkhead(name = "deliveryService")
        @CircuitBreaker(name = "deliveryService")
        @Retry(name = "deliveryService")
        public void create(String deliveryId, String ownerId, String packageId,
                           Location pickup, Location dropoff, TimeWindow window,
                           String correlationId) {
            client.put()
                    .uri("/api/v1/deliveries/{id}", deliveryId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .body(Map.of(
                            "ownerId", ownerId,
                            "packageId", packageId,
                            "pickup", point(pickup),
                            "dropoff", point(dropoff),
                            "pickupWindow", Map.of(
                                    "earliest", window == null ? Instant.now() : window.earliest(),
                                    "latest", window == null ? Instant.now().plusSeconds(3600)
                                                             : window.latest())))
                    .retrieve()
                    .toBodilessEntity();
        }

        @Override
        @Bulkhead(name = "deliveryService")
        @Retry(name = "deliveryService")
        public void assignDrone(String deliveryId, String droneId, String correlationId) {
            client.put()
                    .uri("/api/v1/deliveries/{id}/drone", deliveryId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .body(Map.of("droneId", droneId))
                    .retrieve()
                    .toBodilessEntity();
        }

        @Override
        public void delegateToThirdParty(String deliveryId, String externalTrackingId,
                                         String correlationId) {
            client.put()
                    .uri("/api/v1/deliveries/{id}/delegation", deliveryId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .body(Map.of("externalTrackingId", externalTrackingId))
                    .retrieve()
                    .onStatus(HttpStatusCode::is4xxClientError, (req, res) -> { })
                    .toBodilessEntity();
        }

        @Override
        public void markFailed(String deliveryId, String reason, String correlationId) {
            client.put()
                    .uri("/api/v1/deliveries/{id}/failure", deliveryId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .body(Map.of("reason", reason))
                    .retrieve()
                    .onStatus(HttpStatusCode::is4xxClientError, (req, res) -> { })
                    .toBodilessEntity();
        }

        @Override
        @Retry(name = "deliveryService")
        public void delete(String deliveryId, String correlationId) {
            client.delete()
                    .uri("/api/v1/deliveries/{id}/compensate", deliveryId)
                    .header(Headers.CORRELATION_ID, correlationId)
                    .retrieve()
                    .onStatus(HttpStatusCode::is4xxClientError, (req, res) -> { })
                    .toBodilessEntity();
        }

        private static Map<String, Object> point(Location l) {
            return Map.of("latitude", l.latitude(), "longitude", l.longitude(),
                    "altitude", l.altitude());
        }
    }
}
