package com.fabrikam.drone.contract.event;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("DomainEvent 봉투")
class DomainEventTest {

    private final ObjectMapper mapper = new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .findAndRegisterModules();

    @Test
    @DisplayName("직렬화 → 역직렬화 왕복에서 값이 보존된다")
    void roundTrip() throws Exception {
        DomainEvent e = DomainEvent.of(EventTypes.DELIVERY_CREATED, "dlv-0001",
                "req-abc123", Map.of("ownerId", "acc-0001"));

        String json = mapper.writeValueAsString(e);
        DomainEvent back = mapper.readValue(json, DomainEvent.class);

        assertEquals(e.eventId(), back.eventId());
        assertEquals(e.eventType(), back.eventType());
        assertEquals(e.aggregateId(), back.aggregateId());
        assertEquals(e.correlationId(), back.correlationId());
        assertEquals(e.data(), back.data());
    }

    @Test
    @DisplayName("eventId 는 매번 다르다 — 멱등 소비의 열쇠")
    void uniqueEventId() {
        DomainEvent a = DomainEvent.of(EventTypes.DELIVERY_CREATED, "dlv-1", "r", Map.of());
        DomainEvent b = DomainEvent.of(EventTypes.DELIVERY_CREATED, "dlv-1", "r", Map.of());
        assertNotEquals(a.eventId(), b.eventId());
    }

    @Test
    @DisplayName("후속 이벤트는 상관 ID 를 이어받고 원인 ID 를 기록한다")
    void causationChain() {
        DomainEvent first = DomainEvent.of(EventTypes.DELIVERY_CREATED, "dlv-1", "req-1", Map.of());
        DomainEvent next  = first.caused(EventTypes.DRONE_ASSIGNED, "drn-1", Map.of());

        assertEquals("req-1", next.correlationId(), "상관 ID 가 끊기면 분산 추적이 무너진다");
        assertEquals(first.eventId(), next.causationId());
    }

    @Test
    @DisplayName("필수 필드가 없으면 생성되지 않는다")
    void requiresMandatoryFields() {
        assertThrows(IllegalArgumentException.class,
                () -> DomainEvent.of(null, "dlv-1", "r", Map.of()));
        assertThrows(IllegalArgumentException.class,
                () -> DomainEvent.of(EventTypes.DELIVERY_CREATED, null, "r", Map.of()));
    }

    @Test
    @DisplayName("data 는 불변이다 — 소비자가 원본을 바꿀 수 없다")
    void immutableData() {
        DomainEvent e = DomainEvent.of(EventTypes.DELIVERY_CREATED, "dlv-1", "r",
                Map.of("k", "v"));
        assertThrows(UnsupportedOperationException.class, () -> e.data().put("x", "y"));
    }
}
