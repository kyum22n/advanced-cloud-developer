package com.fabrikam.drone.delivery.domain;

import com.fabrikam.drone.contract.vo.Eta;
import com.fabrikam.drone.contract.vo.Location;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("EtaCalculator 도메인 서비스")
class EtaCalculatorTest {

    private final Instant now = Instant.parse("2026-08-29T10:00:00Z");
    private final EtaCalculator calc = EtaCalculator.standard();   // 60km/h · 오버헤드 4분

    @Test
    @DisplayName("ETA 는 항상 현재보다 미래다 — INV-06 을 만족시킨다")
    void alwaysFuture() {
        Location a = Location.ofGround(37.5665, 126.9780);
        Eta eta = calc.estimate(a, a, now, 0.9);          // 거리 0
        assertTrue(eta.isFuture(), "거리가 0이어도 이착륙 시간 때문에 미래여야 합니다");
    }

    @Test
    @DisplayName("먼 거리일수록 ETA 가 늦다")
    void fartherIsLater() {
        Location from = Location.ofGround(37.5665, 126.9780);
        Location near = Location.ofGround(37.5700, 126.9800);
        Location far  = Location.ofGround(37.5172, 127.0473);

        Eta etaNear = calc.estimate(from, near, now, 0.9);
        Eta etaFar  = calc.estimate(from, far, now, 0.9);
        assertTrue(etaFar.arrivalTime().isAfter(etaNear.arrivalTime()));
    }

    @Test
    @DisplayName("10km 를 60km/h 로 가면 약 10분 + 오버헤드 4분 = 약 14분")
    void plausibleDuration() {
        Location cityHall = Location.ofGround(37.5665, 126.9780);
        Location jamsil   = Location.ofGround(37.5172, 127.0473);

        Eta eta = calc.estimate(cityHall, jamsil, now, 0.9);
        Duration d = Duration.between(now, eta.arrivalTime());
        assertTrue(d.toMinutes() >= 9 && d.toMinutes() <= 20,
                "예상 범위를 벗어남: " + d.toMinutes() + "분");
    }

    @Test
    @DisplayName("오래된 위치로 계산하면 신뢰도가 낮아진다")
    void confidenceDecaysWithStaleness() {
        assertEquals(0.95, calc.confidenceFor(now, now.plusSeconds(10)));
        assertEquals(0.80, calc.confidenceFor(now, now.plusSeconds(100)));
        assertEquals(0.60, calc.confidenceFor(now, now.plusSeconds(250)));
        assertEquals(0.40, calc.confidenceFor(now, now.plusSeconds(600)));
    }

    @Test
    @DisplayName("순항 속도가 0 이하면 계산기를 만들 수 없다")
    void rejectsInvalidSpeed() {
        assertThrows(IllegalArgumentException.class,
                () -> new EtaCalculator(0, Duration.ZERO));
        assertThrows(IllegalArgumentException.class,
                () -> new EtaCalculator(-10, Duration.ZERO));
    }
}
