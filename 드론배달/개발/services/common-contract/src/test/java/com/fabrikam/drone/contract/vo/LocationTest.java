package com.fabrikam.drone.contract.vo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Location 값 개체")
class LocationTest {

    @Test
    @DisplayName("좌표가 같으면 같은 위치다 — 값 개체의 정의")
    void equalByValue() {
        assertEquals(new Location(37.5665, 126.9780, 0),
                     new Location(37.5665, 126.9780, 0));
    }

    @Test
    @DisplayName("위도가 범위를 벗어나면 생성되지 않는다")
    void rejectsInvalidLatitude() {
        assertThrows(IllegalArgumentException.class, () -> new Location(91, 0, 0));
        assertThrows(IllegalArgumentException.class, () -> new Location(-91, 0, 0));
    }

    @Test
    @DisplayName("경도가 범위를 벗어나면 생성되지 않는다")
    void rejectsInvalidLongitude() {
        assertThrows(IllegalArgumentException.class, () -> new Location(0, 181, 0));
    }

    @Test
    @DisplayName("고도는 음수일 수 없다")
    void rejectsNegativeAltitude() {
        assertThrows(IllegalArgumentException.class, () -> new Location(0, 0, -1));
    }

    @Test
    @DisplayName("서울시청 ↔ 잠실 거리는 약 10km 다")
    void computesDistance() {
        Location cityHall = Location.ofGround(37.5665, 126.9780);
        Location jamsil   = Location.ofGround(37.5172, 127.0473);
        double km = cityHall.distanceKmTo(jamsil);
        assertTrue(km > 6 && km < 12, "예상 범위를 벗어남: " + km);
    }

    @Test
    @DisplayName("자기 자신과의 거리는 0 이다")
    void zeroDistanceToSelf() {
        Location l = Location.ofGround(37.5, 127.0);
        assertEquals(0.0, l.distanceKmTo(l), 1e-9);
    }
}
