package com.fabrikam.drone.workflow.infrastructure.acl;

import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.contract.vo.PackageWeight;
import com.fabrikam.drone.workflow.agent.ThirdPartyTransportPort;
import io.github.resilience4j.bulkhead.annotation.Bulkhead;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.Optional;

/**
 * 타사 운송 어댑터 — <b>손상 방지 계층(Anti-Corruption Layer)</b>.
 *
 * <h2>이 클래스가 하는 일</h2>
 * <ol>
 *   <li>우리 도메인 개념 → 외부 스키마로 <b>번역</b></li>
 *   <li>외부 응답 → 우리 도메인 개념으로 <b>역번역</b></li>
 *   <li>외부 장애를 <b>격리</b> (회로 차단기 + Bulkhead)</li>
 * </ol>
 *
 * <h2>왜 필요한가</h2>
 * 외부 API 는 {@code ref_no}, {@code stat_cd}, {@code wt_kg} 같은 자기 용어를 쓴다.
 * 이 용어가 우리 도메인 코드에 들어오면, 외부가 스키마를 바꿀 때 <b>도메인이 함께 흔들린다</b>.
 * 번역을 한 곳에 가두면 외부 변경의 파급이 이 파일에서 멈춘다.
 *
 * <h2>회로 차단기를 «빨리 여는» 이유</h2>
 * 외부 시스템은 우리가 통제할 수 없고, 장애가 오래 지속되는 경향이 있다.
 * 내부 서비스(실패율 50%)보다 낮은 임계값(30%)으로 빨리 차단하고,
 * 대기 큐 없이(Bulkhead 0) 즉시 거부해 우리 스레드를 지킨다.
 */
@Component
public class ThirdPartyTransportAdapter implements ThirdPartyTransportPort {

    private static final Logger log = LoggerFactory.getLogger(ThirdPartyTransportAdapter.class);

    private final RestClient client;

    public ThirdPartyTransportAdapter(RestClient thirdPartyRestClient) {
        this.client = thirdPartyRestClient;
    }

    @Override
    @Bulkhead(name = "thirdParty")
    @CircuitBreaker(name = "thirdParty", fallbackMethod = "unavailable")
    public Optional<String> delegate(String deliveryId, Location pickup, Location dropoff,
                                     PackageWeight weight, String correlationId) {
        // ── ① 도메인 → 외부 스키마 번역
        ExternalShipmentRequest request = new ExternalShipmentRequest(
                deliveryId,                                       // deliveryId    → ref_no
                new ExternalPoint(pickup.latitude(), pickup.longitude()),   // Location → orig
                new ExternalPoint(dropoff.latitude(), dropoff.longitude()), // Location → dest
                weight == null ? null : weight.toKilograms().doubleValue()); // PackageWeight → wt_kg

        ExternalShipmentResponse response = client.post()
                .uri("/v2/shipments")
                .header("X-Correlation-Id", correlationId)
                .body(request)
                .retrieve()
                .body(ExternalShipmentResponse.class);

        if (response == null || response.trackingRef() == null) {
            return Optional.empty();
        }
        // ── ② 외부 → 도메인 역번역
        log.info("타사 위탁 완료 — 외부 추적 번호 확보");
        return Optional.of(response.trackingRef());
    }

    /**
     * 폴백 — 회로가 열려 있거나 격벽이 가득 찼을 때.
     *
     * <p>예외를 던지지 않고 «빈 결과»를 돌려준다. 타사 위탁 실패는
     * <b>예외적 상황이 아니라 정상적인 결과의 한 종류</b>이기 때문이다.
     */
    @SuppressWarnings("unused")
    private Optional<String> unavailable(String deliveryId, Location pickup, Location dropoff,
                                         PackageWeight weight, String correlationId,
                                         Throwable t) {
        log.warn("타사 운송 사용 불가 — 폴백: {}", t.getClass().getSimpleName());
        return Optional.empty();
    }

    // ─────────────────────────────────────────────────────────────
    //  외부 스키마 — 이 용어들은 이 파일 밖으로 나가지 않는다.
    //  ref_no · orig · dest · wt_kg · stat_cd 는 우리 도메인의 단어가 아니다.
    // ─────────────────────────────────────────────────────────────

    record ExternalPoint(double lat, double lng) {
    }

    record ExternalShipmentRequest(String refNo, ExternalPoint orig,
                                   ExternalPoint dest, Double wtKg) {
    }

    record ExternalShipmentResponse(String trackingRef, String statCd) {
    }
}
