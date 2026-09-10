package com.fabrikam.drone.delivery.domain;

import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.contract.vo.TimeWindow;

import java.time.Duration;
import java.time.Instant;

/** 테스트 고정물 — 반복되는 준비 코드를 한곳에 모은다. */
final class DeliveryFixtures {

    static final Instant NOW = Instant.parse("2026-08-29T10:00:00Z");
    static final Location PICKUP  = Location.ofGround(37.5665, 126.9780);   // 서울시청
    static final Location DROPOFF = Location.ofGround(37.5172, 127.0473);   // 잠실
    static final String CORRELATION = "req-test-0001";

    private DeliveryFixtures() {
    }

    static TimeWindow window() {
        return new TimeWindow(NOW.plus(Duration.ofMinutes(10)), NOW.plus(Duration.ofHours(1)));
    }

    /** PENDING 상태의 배달. */
    static Delivery pending() {
        return Delivery.create(DeliveryId.of("dlv-test-0001"), "acc-0001", "pkg-0001",
                PICKUP, DROPOFF, window(), CORRELATION, NOW);
    }

    /** SCHEDULED 상태 — 드론이 할당된 배달. */
    static Delivery scheduled() {
        Delivery d = pending();
        d.assignDrone("drn-0042", CORRELATION, NOW.plusSeconds(3));
        return d;
    }

    /** IN_TRANSIT 상태 — 이동을 시작한 배달. */
    static Delivery inTransit() {
        Delivery d = scheduled();
        d.markInTransit(NOW.plusSeconds(60));
        return d;
    }

    /** HEADED_TO_DROPOFF 상태. */
    static Delivery headedToDropoff() {
        Delivery d = inTransit();
        d.headToDropoff(CORRELATION, NOW.plusSeconds(120));
        return d;
    }

    static Confirmation confirmation() {
        return new Confirmation("cfm-0001", NOW.plusSeconds(900), DROPOFF, "sig-ref-0001");
    }
}
