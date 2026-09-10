package com.fabrikam.drone.ingestion.application;

import com.fabrikam.drone.contract.vo.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.Map;
import java.util.UUID;

/**
 * 배달 요청 접수 — <b>큐 기반 부하 평준화</b>의 입구.
 *
 * <h2>이 서비스가 하지 않는 일</h2>
 * <ul>
 *   <li>도메인 규칙 판단 — 계정 상태·드론 가용성은 여기서 보지 않는다</li>
 *   <li>데이터 저장 — 멱등 캐시 외에는 아무것도 저장하지 않는다</li>
 *   <li>다른 서비스 호출 — 하나도 부르지 않는다</li>
 * </ul>
 *
 * <p>이렇게 얇게 유지해야 «피크 500 req/s 를 p95 300ms 로 받아내는» 목표를 지킬 수 있다.
 * 여기서 무언가를 더 하려는 유혹이 «바쁜 프런트 엔드» 안티패턴의 시작이다.
 */
@Service
public class IngestionService {

    private static final Logger log = LoggerFactory.getLogger(IngestionService.class);

    private final QueuePublisher queuePublisher;
    private final ObjectMapper mapper;
    private final Counter accepted;
    private final Counter rejected;

    public IngestionService(QueuePublisher queuePublisher, ObjectMapper mapper,
                            MeterRegistry registry) {
        this.queuePublisher = queuePublisher;
        this.mapper = mapper;
        this.accepted = Counter.builder("drone.delivery.requests")
                .description("접수된 배달 요청 수").tag("result", "accepted").register(registry);
        this.rejected = Counter.builder("drone.delivery.requests")
                .description("거부된 배달 요청 수").tag("result", "rejected").register(registry);
    }

    /**
     * 요청을 큐에 넣고 배달 ID 를 돌려준다.
     *
     * @return 생성된 배달 ID — 사용자는 이것으로 추적한다
     */
    public String enqueue(String ownerId, Location pickup, Location dropoff,
                          TimeWindow window, PackageWeight weight, PackageSize size,
                          String description, String correlationId) {

        String deliveryId = "dlv-" + UUID.randomUUID().toString().substring(0, 8);
        String packageId  = "pkg-" + UUID.randomUUID().toString().substring(0, 8);

        Map<String, Object> message = Map.ofEntries(
                Map.entry("deliveryId", deliveryId),
                Map.entry("ownerId", ownerId),
                Map.entry("packageId", packageId),
                Map.entry("pickup", pickup),
                Map.entry("dropoff", dropoff),
                Map.entry("pickupWindow", window),
                Map.entry("packageWeight", weight),
                Map.entry("packageSize", size),
                Map.entry("packageDescription", description == null ? "" : description),
                Map.entry("correlationId", correlationId == null ? "" : correlationId));

        try {
            queuePublisher.publish(deliveryId, mapper.writeValueAsString(message), correlationId);
        } catch (Exception e) {
            rejected.increment();
            throw new IllegalStateException("요청을 큐에 넣지 못했습니다.", e);
        }

        accepted.increment();
        log.info("배달 요청 접수 완료");
        return deliveryId;
    }

    public void enqueueCancellation(String deliveryId, String reason, String correlationId) {
        try {
            queuePublisher.publish(deliveryId, mapper.writeValueAsString(Map.of(
                    "type", "CANCEL", "deliveryId", deliveryId,
                    "reason", reason == null ? "" : reason,
                    "correlationId", correlationId == null ? "" : correlationId)), correlationId);
        } catch (Exception e) {
            throw new IllegalStateException("취소 요청을 큐에 넣지 못했습니다.", e);
        }
    }
}
