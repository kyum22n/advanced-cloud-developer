package com.fabrikam.drone.contract.vo;

import java.util.EnumSet;
import java.util.Set;

/**
 * 배달 상태 — 값 개체(열거) + 허용 전이 규칙.
 *
 * <p>전이 규칙을 열거형 자신이 알고 있으면, 상태 기계가 코드 한 곳에만 존재한다.
 * 여러 곳에 {@code if (status == ...)} 가 흩어지는 것을 막는다.
 *
 * <pre>
 *   PENDING ──▶ SCHEDULED ──▶ IN_TRANSIT ──▶ HEADED_TO_DROPOFF ──▶ COMPLETED
 *      │            │              │                 │
 *      │            │              └────────┬────────┘
 *      │            │                       ▼
 *      │            │                    FAILED ──▶ COMPENSATED
 *      ├──▶ DELEGATED ──▶ COMPLETED
 *      └──▶ CANCELLED ◀───┘ (SCHEDULED 까지만)
 * </pre>
 */
public enum DeliveryStatus {
    PENDING,
    SCHEDULED,
    DELEGATED,
    IN_TRANSIT,
    HEADED_TO_DROPOFF,
    COMPLETED,
    CANCELLED,
    FAILED,
    COMPENSATED;

    private static final Set<DeliveryStatus> TERMINAL =
            EnumSet.of(COMPLETED, CANCELLED, COMPENSATED);

    /** INV-04 — 종료 상태에서는 어떤 전이도 허용되지 않는다. */
    public boolean isTerminal() {
        return TERMINAL.contains(this);
    }

    /** INV-01 — IN_TRANSIT 이후에는 취소할 수 없다. */
    public boolean isCancellable() {
        return this == PENDING || this == SCHEDULED;
    }

    public boolean canTransitionTo(DeliveryStatus next) {
        if (isTerminal()) {
            return false;
        }
        return switch (this) {
            case PENDING           -> next == SCHEDULED || next == DELEGATED
                                   || next == CANCELLED || next == FAILED;
            case SCHEDULED         -> next == IN_TRANSIT || next == CANCELLED || next == FAILED;
            case DELEGATED         -> next == COMPLETED  || next == FAILED;
            case IN_TRANSIT        -> next == HEADED_TO_DROPOFF || next == FAILED;
            case HEADED_TO_DROPOFF -> next == COMPLETED  || next == FAILED;
            case FAILED            -> next == COMPENSATED;
            default                -> false;
        };
    }
}
