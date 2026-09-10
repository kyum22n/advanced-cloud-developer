package com.fabrikam.drone.history.application;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.history.domain.DeliveryHistoryEntry;
import com.fabrikam.drone.history.domain.DeliveryHistoryRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.Optional;

/**
 * DeliveryTracking 이벤트 소비 — <b>멱등 소비자</b>.
 *
 * <h2>왜 멱등성이 필수인가</h2>
 * Event Hubs 는 «최소 1회» 전달이다. 체크포인트를 찍기 전에 인스턴스가 죽으면
 * 같은 이벤트를 다시 받는다. 멱등 처리가 없으면 이력이 중복되고 통계가 틀어진다.
 *
 * <h2>두 겹의 방어</h2>
 * ① {@code eventId} 기반 중복 제거 (이 클래스)
 * ② 이력 항목 자신의 «같은 유형 이정표는 덮어쓰지 않음» (도메인)
 * 하나만 있어도 대부분 막히지만, 둘 다 두어 저장소 장애 시에도 견디게 한다.
 */
@Service
public class HistoryEventHandler {

    private static final Logger log = LoggerFactory.getLogger(HistoryEventHandler.class);
    private static final Duration DEDUP_TTL = Duration.ofHours(24);

    private final DeliveryHistoryRepository repository;
    private final ProcessedEventStore processedEvents;

    public HistoryEventHandler(DeliveryHistoryRepository repository,
                               ProcessedEventStore processedEvents) {
        this.repository = repository;
        this.processedEvents = processedEvents;
    }

    /**
     * 이벤트를 처리한다.
     *
     * <p>처리에 성공한 뒤에만 호출자가 체크포인트를 찍어야 한다.
     * 자동 체크포인트를 쓰면 «수신했지만 처리 실패»한 이벤트가 조용히 사라진다.
     */
    public void handle(DomainEvent event) {
        MDC.put("correlationId", event.correlationId());
        MDC.put("deliveryId", event.aggregateId());
        try {
            if (!processedEvents.markIfAbsent(event.eventId(), DEDUP_TTL)) {
                log.debug("중복 이벤트 — 무시합니다");
                return;
            }

            DeliveryHistoryEntry entry = repository.findById(event.aggregateId())
                    .orElseGet(() -> new DeliveryHistoryEntry(event.aggregateId()));

            entry.apply(event.eventType(), event.occurredAt(), event.data());
            repository.save(entry);

            log.info("이력 반영: {}", event.eventType());
        } finally {
            MDC.clear();
        }
    }

    public Optional<DeliveryHistoryEntry> find(String deliveryId) {
        return repository.findById(deliveryId);
    }

    /** 중복 제거 저장소 — 포트. */
    public interface ProcessedEventStore {
        /** 처음 보는 이벤트면 true. 원자적이어야 한다. */
        boolean markIfAbsent(String eventId, Duration ttl);
    }
}
