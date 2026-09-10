package com.fabrikam.drone.history.application;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.contract.event.EventTypes;
import com.fabrikam.drone.history.domain.DeliveryHistoryEntry;
import com.fabrikam.drone.history.domain.DeliveryHistoryRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("HistoryEventHandler — 멱등 소비자")
class HistoryEventHandlerTest {

    private InMemoryRepo repo;
    private HistoryEventHandler handler;

    @BeforeEach
    void setUp() {
        repo = new InMemoryRepo();
        Set<String> seen = ConcurrentHashMap.newKeySet();
        handler = new HistoryEventHandler(repo, (eventId, ttl) -> seen.add(eventId));
    }

    @Test
    @DisplayName("이벤트를 받아 이력을 만든다")
    void createsEntry() {
        handler.handle(DomainEvent.of(EventTypes.DELIVERY_CREATED, "dlv-0001", "req-1",
                Map.of("ownerId", "acc-0001", "packageId", "pkg-0001")));

        var entry = handler.find("dlv-0001").orElseThrow();
        assertEquals("acc-0001", entry.ownerId());
    }

    @Test
    @DisplayName("같은 eventId 의 이벤트를 두 번 받아도 한 번만 반영한다")
    void idempotentByEventId() {
        DomainEvent event = DomainEvent.of(EventTypes.DELIVERY_CREATED, "dlv-0001", "req-1",
                Map.of("ownerId", "acc-0001"));

        handler.handle(event);
        handler.handle(event);                              // 재전달

        assertEquals(1, repo.saveCount, "중복 이벤트가 저장을 두 번 일으키면 안 됩니다");
    }

    @Test
    @DisplayName("서로 다른 이벤트는 모두 반영된다")
    void appliesDistinctEvents() {
        handler.handle(DomainEvent.of(EventTypes.DELIVERY_CREATED, "dlv-0001", "req-1",
                Map.of("ownerId", "acc-0001")));
        handler.handle(DomainEvent.of(EventTypes.DELIVERY_COMPLETED, "dlv-0001", "req-1",
                Map.of()));

        var entry = handler.find("dlv-0001").orElseThrow();
        assertEquals("COMPLETED", entry.finalStatus());
        assertEquals(2, entry.milestones().size());
    }

    @Test
    @DisplayName("이력이 없는 배달을 조회하면 비어 있다")
    void emptyWhenUnknown() {
        assertTrue(handler.find("dlv-unknown").isEmpty());
    }

    static class InMemoryRepo implements DeliveryHistoryRepository {
        final Map<String, DeliveryHistoryEntry> store = new HashMap<>();
        int saveCount = 0;

        @Override public Optional<DeliveryHistoryEntry> findById(String id) {
            return Optional.ofNullable(store.get(id));
        }

        @Override public void save(DeliveryHistoryEntry entry) {
            store.put(entry.deliveryId(), entry);
            saveCount++;
        }

        @Override public List<DeliveryHistoryEntry> findByPeriod(String ownerId, Instant from,
                                                                 Instant to, int page, int size) {
            return List.copyOf(store.values());
        }

        @Override public Summary summarize(String ownerId, Instant from, Instant to) {
            return new Summary(0, 0, 0, 0);
        }
    }
}
