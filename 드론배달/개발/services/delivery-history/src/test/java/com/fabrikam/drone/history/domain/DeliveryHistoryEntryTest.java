package com.fabrikam.drone.history.domain;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("DeliveryHistoryEntry — 이벤트로 만드는 읽기 모델")
class DeliveryHistoryEntryTest {

    private static final Instant T0 = Instant.parse("2026-08-29T10:00:00Z");

    @Test
    @DisplayName("이벤트를 순서대로 반영해 이력을 구성한다")
    void buildsFromEvents() {
        DeliveryHistoryEntry e = new DeliveryHistoryEntry("dlv-0001");
        e.apply("DeliveryCreated", T0,
                Map.of("ownerId", "acc-0001", "packageId", "pkg-0001"));
        e.apply("DroneAssigned", T0.plusSeconds(3), Map.of("droneId", "drn-0042"));
        e.apply("DeliveryHeadedToDropoff", T0.plusSeconds(120), Map.of());
        e.apply("DeliveryCompleted", T0.plusSeconds(900), Map.of());

        assertEquals("acc-0001", e.ownerId());
        assertEquals("pkg-0001", e.packageId());
        assertEquals("drn-0042", e.droneId());
        assertEquals("COMPLETED", e.finalStatus());
        assertEquals(900, e.durationSeconds());
        assertEquals(4, e.milestones().size());
        assertTrue(e.isFinished());
    }

    @Test
    @DisplayName("같은 유형의 이벤트가 두 번 오면 무시한다 — 최소 1회 전달 대비")
    void ignoresDuplicateEventType() {
        DeliveryHistoryEntry e = new DeliveryHistoryEntry("dlv-0001");
        e.apply("DeliveryCreated", T0, Map.of("ownerId", "acc-0001"));
        e.apply("DeliveryCreated", T0.plusSeconds(1), Map.of("ownerId", "acc-9999"));

        assertEquals(1, e.milestones().size());
        assertEquals("acc-0001", e.ownerId(), "첫 이벤트가 이겨야 합니다");
    }

    @Test
    @DisplayName("알 수 없는 이벤트 유형이 와도 깨지지 않는다 — 하위 호환")
    void toleratesUnknownEventType() {
        DeliveryHistoryEntry e = new DeliveryHistoryEntry("dlv-0001");
        e.apply("DeliveryCreated", T0, Map.of("ownerId", "acc-0001"));

        assertDoesNotThrow(() -> e.apply("SomeFutureEvent", T0.plusSeconds(5), Map.of()));
        assertEquals("PENDING", e.finalStatus(), "알 수 없는 이벤트가 상태를 바꾸면 안 됩니다");
        assertEquals(2, e.milestones().size(), "이정표로는 남겨 둡니다");
    }

    @Test
    @DisplayName("실패 이벤트는 사유를 기록한다")
    void recordsFailureReason() {
        DeliveryHistoryEntry e = new DeliveryHistoryEntry("dlv-0001");
        e.apply("DeliveryCreated", T0, Map.of("ownerId", "acc-0001"));
        e.apply("DeliveryFailed", T0.plusSeconds(300), Map.of("reason", "드론 통신 두절"));

        assertEquals("FAILED", e.finalStatus());
        assertEquals("드론 통신 두절", e.failureReason());
    }

    @Test
    @DisplayName("아직 끝나지 않은 배달의 소요 시간은 -1 이다")
    void durationIsMinusOneWhenUnfinished() {
        DeliveryHistoryEntry e = new DeliveryHistoryEntry("dlv-0001");
        e.apply("DeliveryCreated", T0, Map.of("ownerId", "acc-0001"));

        assertEquals(-1, e.durationSeconds());
        assertFalse(e.isFinished());
    }

    @Test
    @DisplayName("배달 ID 없이는 만들 수 없다")
    void requiresDeliveryId() {
        assertThrows(IllegalArgumentException.class, () -> new DeliveryHistoryEntry(null));
        assertThrows(IllegalArgumentException.class, () -> new DeliveryHistoryEntry("  "));
    }

    @Test
    @DisplayName("이정표 목록은 밖에서 바꿀 수 없다")
    void milestonesAreImmutable() {
        DeliveryHistoryEntry e = new DeliveryHistoryEntry("dlv-0001");
        assertThrows(UnsupportedOperationException.class,
                () -> e.milestones().add(new DeliveryHistoryEntry.Milestone("X", T0, "Y")));
    }
}
