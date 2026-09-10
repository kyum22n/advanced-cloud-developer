package com.fabrikam.drone.contract.vo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Eta 값 개체")
class EtaTest {

    private final Instant now = Instant.parse("2026-08-29T10:00:00Z");

    @Test
    @DisplayName("INV-06 — 도착 시각이 산출 시각보다 미래여야 유효하다")
    void inv06_mustBeFuture() {
        assertTrue(new Eta(now.plus(Duration.ofMinutes(30)), now, 0.9).isFuture());
        assertFalse(new Eta(now.minus(Duration.ofMinutes(1)), now, 0.9).isFuture());
    }

    @Test
    @DisplayName("신뢰도는 0.0 ~ 1.0 이어야 한다")
    void confidenceRange() {
        assertThrows(IllegalArgumentException.class, () -> new Eta(now.plusSeconds(60), now, 1.1));
        assertThrows(IllegalArgumentException.class, () -> new Eta(now.plusSeconds(60), now, -0.1));
    }

    @Test
    @DisplayName("남은 시간은 음수가 되지 않는다")
    void remainingNeverNegative() {
        Eta past = new Eta(now.plusSeconds(1), now, 0.9);
        assertEquals(Duration.ZERO, past.remaining(now.plusSeconds(600)));
    }
}
