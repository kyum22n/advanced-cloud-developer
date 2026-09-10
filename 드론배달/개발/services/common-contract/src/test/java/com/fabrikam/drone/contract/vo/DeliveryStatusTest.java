package com.fabrikam.drone.contract.vo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import static com.fabrikam.drone.contract.vo.DeliveryStatus.*;
import static org.junit.jupiter.api.Assertions.*;

@DisplayName("DeliveryStatus 상태 기계")
class DeliveryStatusTest {

    @Test
    @DisplayName("INV-01 — IN_TRANSIT 이후에는 취소할 수 없다")
    void inv01_notCancellableAfterInTransit() {
        assertTrue(PENDING.isCancellable());
        assertTrue(SCHEDULED.isCancellable());
        assertFalse(IN_TRANSIT.isCancellable());
        assertFalse(HEADED_TO_DROPOFF.isCancellable());
    }

    @ParameterizedTest
    @EnumSource(value = DeliveryStatus.class, names = {"COMPLETED", "CANCELLED", "COMPENSATED"})
    @DisplayName("INV-04 — 종료 상태에서는 어떤 전이도 불가하다")
    void inv04_terminalRejectsAll(DeliveryStatus terminal) {
        assertTrue(terminal.isTerminal());
        for (DeliveryStatus next : DeliveryStatus.values()) {
            assertFalse(terminal.canTransitionTo(next),
                    terminal + " → " + next + " 가 허용되어서는 안 됩니다.");
        }
    }

    @Test
    @DisplayName("정상 경로 — PENDING → SCHEDULED → IN_TRANSIT → HEADED_TO_DROPOFF → COMPLETED")
    void happyPath() {
        assertTrue(PENDING.canTransitionTo(SCHEDULED));
        assertTrue(SCHEDULED.canTransitionTo(IN_TRANSIT));
        assertTrue(IN_TRANSIT.canTransitionTo(HEADED_TO_DROPOFF));
        assertTrue(HEADED_TO_DROPOFF.canTransitionTo(COMPLETED));
    }

    @Test
    @DisplayName("위탁 경로 — PENDING → DELEGATED → COMPLETED")
    void delegatedPath() {
        assertTrue(PENDING.canTransitionTo(DELEGATED));
        assertTrue(DELEGATED.canTransitionTo(COMPLETED));
    }

    @Test
    @DisplayName("보상 경로 — FAILED → COMPENSATED 만 허용")
    void compensationPath() {
        assertTrue(FAILED.canTransitionTo(COMPENSATED));
        assertFalse(FAILED.canTransitionTo(COMPLETED));
        assertFalse(FAILED.canTransitionTo(PENDING));
    }

    @Test
    @DisplayName("건너뛰기는 허용되지 않는다 — PENDING 에서 바로 COMPLETED 불가")
    void noSkipping() {
        assertFalse(PENDING.canTransitionTo(COMPLETED));
        assertFalse(PENDING.canTransitionTo(IN_TRANSIT));
        assertFalse(SCHEDULED.canTransitionTo(COMPLETED));
    }
}
