package com.fabrikam.drone.delivery.domain;

import com.fabrikam.drone.contract.vo.DeliveryStatus;
import com.fabrikam.drone.contract.vo.Eta;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static com.fabrikam.drone.delivery.domain.DeliveryFixtures.*;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Delivery 애그리거트 불변식 테스트.
 *
 * <p>분석/03 에서 도출한 INV-01 · 02 · 04 · 05 · 06 각각에 테스트가 대응한다.
 * (INV-03 은 Drone 애그리거트의 책임이므로 drone-scheduler 서비스에서 검증한다.)
 */
@DisplayName("Delivery 애그리거트 — 도메인 불변식")
class DeliveryInvariantTest {

    @Nested
    @DisplayName("INV-01 — IN_TRANSIT 이후에는 취소할 수 없다")
    class Inv01 {

        @Test
        @DisplayName("PENDING 상태에서는 취소된다")
        void cancellableWhenPending() {
            Delivery d = pending();
            d.cancel("사용자 요청", CORRELATION, NOW.plusSeconds(30));
            assertEquals(DeliveryStatus.CANCELLED, d.status());
        }

        @Test
        @DisplayName("SCHEDULED 상태에서도 취소된다")
        void cancellableWhenScheduled() {
            Delivery d = scheduled();
            d.cancel("사용자 요청", CORRELATION, NOW.plusSeconds(30));
            assertEquals(DeliveryStatus.CANCELLED, d.status());
        }

        @Test
        @DisplayName("IN_TRANSIT 상태에서는 취소가 거부된다")
        void notCancellableWhenInTransit() {
            Delivery d = inTransit();
            var e = assertThrows(InvalidStateTransitionException.class,
                    () -> d.cancel("너무 늦음", CORRELATION, NOW.plusSeconds(90)));
            assertEquals(DeliveryStatus.IN_TRANSIT, e.from());
            assertEquals(DeliveryStatus.IN_TRANSIT, d.status(), "실패해도 상태는 변하지 않아야 합니다");
        }

        @Test
        @DisplayName("HEADED_TO_DROPOFF 상태에서도 취소가 거부된다")
        void notCancellableWhenHeadedToDropoff() {
            Delivery d = headedToDropoff();
            assertThrows(InvalidStateTransitionException.class,
                    () -> d.cancel("늦음", CORRELATION, NOW.plusSeconds(150)));
        }
    }

    @Nested
    @DisplayName("INV-02 — 드론이 할당되지 않으면 IN_TRANSIT 이 될 수 없다")
    class Inv02 {

        @Test
        @DisplayName("드론 없이 이동 시작을 시도하면 거부된다")
        void requiresDrone() {
            Delivery d = pending();
            assertThrows(InvalidStateTransitionException.class,
                    () -> d.markInTransit(NOW.plusSeconds(60)));
            assertEquals(DeliveryStatus.PENDING, d.status());
        }

        @Test
        @DisplayName("드론이 할당되면 이동을 시작할 수 있다")
        void allowedWithDrone() {
            Delivery d = scheduled();
            d.markInTransit(NOW.plusSeconds(60));
            assertEquals(DeliveryStatus.IN_TRANSIT, d.status());
            assertEquals("drn-0042", d.droneId());
        }
    }

    @Nested
    @DisplayName("INV-04 — 종료 상태에서는 어떤 전이도 불가하다")
    class Inv04 {

        @Test
        @DisplayName("완료된 배달은 취소할 수 없다")
        void completedCannotBeCancelled() {
            Delivery d = headedToDropoff();
            d.complete(confirmation(), CORRELATION, NOW.plusSeconds(900));
            assertThrows(InvalidStateTransitionException.class,
                    () -> d.cancel("취소", CORRELATION, NOW.plusSeconds(1000)));
        }

        @Test
        @DisplayName("취소된 배달은 드론을 할당할 수 없다")
        void cancelledCannotAssignDrone() {
            Delivery d = pending();
            d.cancel("사용자 요청", CORRELATION, NOW.plusSeconds(30));
            assertThrows(InvalidStateTransitionException.class,
                    () -> d.assignDrone("drn-0099", CORRELATION, NOW.plusSeconds(40)));
        }

        @Test
        @DisplayName("완료된 배달은 ETA 를 갱신할 수 없다")
        void completedCannotUpdateEta() {
            Delivery d = headedToDropoff();
            d.complete(confirmation(), CORRELATION, NOW.plusSeconds(900));
            Eta future = new Eta(NOW.plusSeconds(2000), NOW.plusSeconds(1000), 0.9);
            assertThrows(InvalidStateTransitionException.class,
                    () -> d.updateEta(future, NOW.plusSeconds(1000)));
        }
    }

    @Nested
    @DisplayName("INV-05 — 배달은 반드시 패키지를 참조한다")
    class Inv05 {

        @Test
        @DisplayName("패키지 ID 가 없으면 생성되지 않는다")
        void requiresPackageId() {
            assertThrows(IllegalArgumentException.class,
                    () -> Delivery.create(DeliveryId.of("dlv-x"), "acc-0001", null,
                            PICKUP, DROPOFF, window(), CORRELATION, NOW));
        }

        @Test
        @DisplayName("패키지 ID 가 공백이면 생성되지 않는다")
        void rejectsBlankPackageId() {
            assertThrows(IllegalArgumentException.class,
                    () -> Delivery.create(DeliveryId.of("dlv-x"), "acc-0001", "   ",
                            PICKUP, DROPOFF, window(), CORRELATION, NOW));
        }

        @Test
        @DisplayName("소유 계정이 없으면 생성되지 않는다")
        void requiresOwner() {
            assertThrows(IllegalArgumentException.class,
                    () -> Delivery.create(DeliveryId.of("dlv-x"), null, "pkg-0001",
                            PICKUP, DROPOFF, window(), CORRELATION, NOW));
        }
    }

    @Nested
    @DisplayName("INV-06 — ETA 는 산출 시점보다 미래다")
    class Inv06 {

        @Test
        @DisplayName("과거 ETA 는 거부된다")
        void rejectsPastEta() {
            Delivery d = inTransit();
            Eta past = new Eta(NOW.plusSeconds(10), NOW.plusSeconds(100), 0.9);
            assertThrows(IllegalArgumentException.class,
                    () -> d.updateEta(past, NOW.plusSeconds(100)));
        }

        @Test
        @DisplayName("미래 ETA 는 반영된다")
        void acceptsFutureEta() {
            Delivery d = inTransit();
            Eta future = new Eta(NOW.plusSeconds(1800), NOW.plusSeconds(100), 0.85);
            d.updateEta(future, NOW.plusSeconds(100));
            assertEquals(future, d.eta());
        }

        @Test
        @DisplayName("null ETA 는 거부된다")
        void rejectsNullEta() {
            Delivery d = inTransit();
            assertThrows(IllegalArgumentException.class,
                    () -> d.updateEta(null, NOW.plusSeconds(100)));
        }
    }
}
