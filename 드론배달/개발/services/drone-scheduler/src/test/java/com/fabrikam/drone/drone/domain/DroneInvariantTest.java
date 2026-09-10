package com.fabrikam.drone.drone.domain;

import com.fabrikam.drone.contract.vo.DroneStatus;
import com.fabrikam.drone.contract.vo.Location;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Drone 애그리거트 — 도메인 불변식")
class DroneInvariantTest {

    private static final Instant NOW = Instant.parse("2026-08-29T10:00:00Z");
    private static final Location BASE = Location.ofGround(37.5665, 126.9780);
    private static final BigDecimal CAPACITY = new BigDecimal("5.000");
    private static final String CORR = "req-test";

    private Drone available() {
        return Drone.register(DroneId.of("drn-0042"), CAPACITY, BASE, NOW);
    }

    @Nested
    @DisplayName("INV-03 — 하나의 드론은 동시에 하나의 배달만 수행한다")
    class Inv03 {

        @Test
        @DisplayName("가용 드론은 할당된다")
        void assignsWhenAvailable() {
            Drone d = available();
            d.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW);

            assertEquals(DroneStatus.ASSIGNED, d.status());
            assertEquals("dlv-0001", d.currentDeliveryId().orElseThrow());
        }

        @Test
        @DisplayName("이미 배달 중인 드론에 다른 배달을 할당하면 거부된다")
        void rejectsSecondAssignment() {
            Drone d = available();
            d.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW);

            var e = assertThrows(DroneUnavailableException.class,
                    () -> d.assign("dlv-0002", new BigDecimal("1.0"), CORR, NOW.plusSeconds(1)));

            assertEquals("dlv-0001", e.currentDeliveryId());
            assertEquals("dlv-0001", d.currentDeliveryId().orElseThrow(),
                    "거부되어도 기존 할당은 유지되어야 합니다");
        }

        @Test
        @DisplayName("같은 배달을 다시 할당하는 것은 성공한다 — 재시도 멱등성")
        void sameDeliveryIsIdempotent() {
            Drone d = available();
            d.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW);
            assertDoesNotThrow(
                    () -> d.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW.plusSeconds(1)));
            assertEquals("dlv-0001", d.currentDeliveryId().orElseThrow());
        }

        @Test
        @DisplayName("해제 후에는 다시 할당된다")
        void reassignableAfterRelease() {
            Drone d = available();
            d.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW);
            d.release(CORR, NOW.plusSeconds(600));

            assertEquals(DroneStatus.AVAILABLE, d.status());
            assertTrue(d.currentDeliveryId().isEmpty());
            assertDoesNotThrow(
                    () -> d.assign("dlv-0002", new BigDecimal("1.0"), CORR, NOW.plusSeconds(601)));
        }
    }

    @Nested
    @DisplayName("적재 용량")
    class Capacity {

        @Test
        @DisplayName("용량을 초과하는 무게는 할당되지 않는다")
        void rejectsOverweight() {
            Drone d = available();
            assertThrows(NoAvailableDroneException.class,
                    () -> d.assign("dlv-0001", new BigDecimal("7.0"), CORR, NOW));
        }

        @Test
        @DisplayName("용량과 같은 무게는 할당된다")
        void acceptsExactCapacity() {
            Drone d = available();
            assertDoesNotThrow(() -> d.assign("dlv-0001", CAPACITY, CORR, NOW));
        }
    }

    @Nested
    @DisplayName("배터리")
    class Battery {

        @Test
        @DisplayName("배터리가 30% 미만이면 할당되지 않는다")
        void rejectsLowBattery() {
            Drone d = available();
            d.reportTelemetry(BASE, 25, CORR, NOW);
            assertThrows(DroneUnavailableException.class,
                    () -> d.assign("dlv-0001", new BigDecimal("1.0"), CORR, NOW.plusSeconds(1)));
        }

        @Test
        @DisplayName("배터리가 부족해지면 자동으로 충전 상태가 된다")
        void autoChargingOnLowBattery() {
            Drone d = available();
            d.reportTelemetry(BASE, 20, CORR, NOW);
            assertEquals(DroneStatus.CHARGING, d.status());
        }

        @Test
        @DisplayName("배터리 잔량이 범위를 벗어나면 거부된다")
        void rejectsInvalidBattery() {
            Drone d = available();
            assertThrows(IllegalArgumentException.class,
                    () -> d.reportTelemetry(BASE, 101, CORR, NOW));
            assertThrows(IllegalArgumentException.class,
                    () -> d.reportTelemetry(BASE, -1, CORR, NOW));
        }
    }

    @Nested
    @DisplayName("보상 트랜잭션 멱등성")
    class Compensation {

        @Test
        @DisplayName("할당되지 않은 드론을 해제해도 실패하지 않는다")
        void releaseIsIdempotent() {
            Drone d = available();
            assertDoesNotThrow(() -> d.release(CORR, NOW));
            assertDoesNotThrow(() -> d.release(CORR, NOW.plusSeconds(1)));
            assertEquals(DroneStatus.AVAILABLE, d.status());
        }

        @Test
        @DisplayName("해제를 두 번 해도 상태가 망가지지 않는다")
        void doubleReleaseIsSafe() {
            Drone d = available();
            d.assign("dlv-0001", new BigDecimal("2.0"), CORR, NOW);
            d.release(CORR, NOW.plusSeconds(10));
            d.release(CORR, NOW.plusSeconds(11));
            assertEquals(DroneStatus.AVAILABLE, d.status());
            assertTrue(d.currentDeliveryId().isEmpty());
        }
    }

    @Test
    @DisplayName("배달 중인 드론은 정비 상태로 보낼 수 없다")
    void cannotMaintainWhileAssigned() {
        Drone d = available();
        d.assign("dlv-0001", new BigDecimal("2.0"), CORR, NOW);
        assertThrows(DroneUnavailableException.class, () -> d.enterMaintenance(NOW.plusSeconds(5)));
    }

    @Test
    @DisplayName("텔레메트리는 DroneStatusChanged 이벤트를 낸다")
    void telemetryRaisesEvent() {
        Drone d = available();
        d.drainEvents();
        d.reportTelemetry(Location.ofGround(37.55, 127.0), 80, CORR, NOW);

        var events = d.drainEvents();
        assertEquals(1, events.size());
        assertEquals("DroneStatusChanged", events.get(0).eventType());
        assertEquals(80, events.get(0).data().get("battery"));
    }
}
