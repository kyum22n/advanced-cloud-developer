package com.fabrikam.drone.delivery.domain;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.contract.event.EventTypes;
import com.fabrikam.drone.contract.vo.DeliveryStatus;
import com.fabrikam.drone.contract.vo.Location;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static com.fabrikam.drone.delivery.domain.DeliveryFixtures.*;
import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Delivery 애그리거트 — 수명 주기와 이벤트")
class DeliveryLifecycleTest {

    @Test
    @DisplayName("정상 경로 — 생성 → 할당 → 이동 → 배달지 → 완료")
    void happyPath() {
        Delivery d = pending();
        assertEquals(DeliveryStatus.PENDING, d.status());

        d.assignDrone("drn-0042", CORRELATION, NOW.plusSeconds(3));
        assertEquals(DeliveryStatus.SCHEDULED, d.status());

        d.markInTransit(NOW.plusSeconds(60));
        assertEquals(DeliveryStatus.IN_TRANSIT, d.status());

        d.headToDropoff(CORRELATION, NOW.plusSeconds(120));
        assertEquals(DeliveryStatus.HEADED_TO_DROPOFF, d.status());

        d.complete(confirmation(), CORRELATION, NOW.plusSeconds(900));
        assertEquals(DeliveryStatus.COMPLETED, d.status());
        assertTrue(d.confirmation().isPresent());
    }

    @Test
    @DisplayName("위탁 경로 — 생성 → 타사 위탁 → 완료")
    void delegationPath() {
        Delivery d = pending();
        d.delegateToThirdParty("TP-99887766", CORRELATION, NOW.plusSeconds(5));
        assertEquals(DeliveryStatus.DELEGATED, d.status());

        d.complete(confirmation(), CORRELATION, NOW.plusSeconds(3600));
        assertEquals(DeliveryStatus.COMPLETED, d.status());
    }

    @Test
    @DisplayName("실패 경로 — 실패 후 보상만 가능하다")
    void failureAndCompensation() {
        Delivery d = inTransit();
        d.fail("드론 통신 두절", CORRELATION, NOW.plusSeconds(300));
        assertEquals(DeliveryStatus.FAILED, d.status());

        d.markCompensated(NOW.plusSeconds(360));
        assertEquals(DeliveryStatus.COMPENSATED, d.status());
    }

    @Test
    @DisplayName("생성 시 DeliveryCreated 이벤트가 하나 발생한다")
    void raisesCreatedEvent() {
        Delivery d = pending();
        List<DomainEvent> events = d.drainEvents();

        assertEquals(1, events.size());
        DomainEvent e = events.get(0);
        assertEquals(EventTypes.DELIVERY_CREATED, e.eventType());
        assertEquals("dlv-test-0001", e.aggregateId());
        assertEquals(CORRELATION, e.correlationId(), "상관 ID 가 이벤트로 전파되어야 합니다");
        assertEquals("pkg-0001", e.data().get("packageId"));
    }

    @Test
    @DisplayName("drainEvents 는 한 번만 꺼낸다 — 중복 발행 방지")
    void drainsOnce() {
        Delivery d = pending();
        assertEquals(1, d.drainEvents().size());
        assertEquals(0, d.drainEvents().size(), "이미 꺼낸 이벤트가 다시 나오면 중복 발행됩니다");
    }

    @Test
    @DisplayName("완료 시 DeliveryCompleted 이벤트가 발생한다")
    void raisesCompletedEvent() {
        Delivery d = headedToDropoff();
        d.drainEvents();                                    // 이전 이벤트 비우기
        d.complete(confirmation(), CORRELATION, NOW.plusSeconds(900));

        List<DomainEvent> events = d.drainEvents();
        assertEquals(1, events.size());
        assertEquals(EventTypes.DELIVERY_COMPLETED, events.get(0).eventType());
    }

    @Test
    @DisplayName("상태가 바뀔 때마다 버전이 올라간다 — 낙관적 동시성의 근거")
    void versionIncrements() {
        Delivery d = pending();
        long v0 = d.version();
        d.assignDrone("drn-0042", CORRELATION, NOW.plusSeconds(3));
        assertTrue(d.version() > v0);
    }

    @Test
    @DisplayName("종료된 배달의 위치는 갱신되지 않는다")
    void terminalIgnoresLocation() {
        Delivery d = pending();
        d.cancel("사용자 요청", CORRELATION, NOW.plusSeconds(30));
        long v = d.version();

        d.updateLocation(Location.ofGround(37.55, 127.00), NOW.plusSeconds(40));
        assertEquals(v, d.version(), "종료 상태에서는 아무 일도 일어나지 않아야 합니다");
        assertNull(d.currentLocation());
    }

    @Test
    @DisplayName("다른 애그리거트는 ID 로만 참조한다 — 애그리거트 설계 3원칙")
    void referencesOtherAggregatesById() {
        Delivery d = scheduled();
        // 컴파일 시점 확인 — 이 값들이 객체가 아니라 문자열 ID 다.
        assertInstanceOf(String.class, d.packageId());
        assertInstanceOf(String.class, d.droneId());
        assertInstanceOf(String.class, d.ownerId());
    }
}
