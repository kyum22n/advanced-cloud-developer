package com.fabrikam.drone.delivery.infrastructure;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.contract.event.EventTypes;
import com.fabrikam.drone.delivery.application.DeliveryEventPublisher;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.function.Consumer;

/**
 * Event Hubs 발행 어댑터.
 *
 * <p>파티션 키를 {@code aggregateId} 로 둔다 — 같은 배달의 이벤트가 같은 파티션에 들어가
 * <b>순서가 보장</b>된다. 무작위 키를 쓰면 Completed 가 Created 보다 먼저 처리될 수 있다.
 *
 * <p>실제 전송은 {@code sender} 로 주입한다. 테스트에서는 목록에 담는 구현으로 바꿔 끼운다.
 */
@Component
public class EventHubsDeliveryEventPublisher implements DeliveryEventPublisher {

    private static final Logger log = LoggerFactory.getLogger(EventHubsDeliveryEventPublisher.class);

    private final ObjectMapper mapper;
    private final Consumer<EventEnvelope> sender;
    private final String hubName;

    public EventHubsDeliveryEventPublisher(
            ObjectMapper mapper,
            Consumer<EventEnvelope> sender,
            @Value("${drone.eventhub.delivery-tracking:" + EventTypes.HUB_DELIVERY_TRACKING + "}")
            String hubName) {
        this.mapper = mapper;
        this.sender = sender;
        this.hubName = hubName;
    }

    @Override
    public void publish(DomainEvent event) {
        try {
            String body = mapper.writeValueAsString(event);
            sender.accept(new EventEnvelope(hubName, event.aggregateId(), body,
                    event.eventType(), event.correlationId()));
            log.debug("이벤트 발행: {}", event.eventType());
        } catch (Exception e) {
            // ⚠️ 발행 실패를 삼키면 이벤트가 조용히 사라진다.
            //     상위로 던져 트랜잭션 재시도 또는 아웃박스로 넘긴다.
            throw new IllegalStateException("이벤트 발행 실패: " + event.eventType(), e);
        }
    }

    /**
     * 전송 봉투.
     *
     * @param partitionKey 애그리거트 ID — 순서 보장의 근거
     */
    public record EventEnvelope(String hubName, String partitionKey, String body,
                                String eventType, String correlationId) {
    }
}
