package com.fabrikam.drone.delivery.domain;

import com.fabrikam.drone.contract.vo.DeliveryStatus;

/** 허용되지 않는 상태 전이 — 도메인 불변식 위반. HTTP 409 로 매핑된다. */
public class InvalidStateTransitionException extends RuntimeException {

    private final DeliveryStatus from;
    private final DeliveryStatus to;

    public InvalidStateTransitionException(DeliveryStatus from, DeliveryStatus to) {
        super("허용되지 않는 상태 전이입니다: %s → %s".formatted(from, to));
        this.from = from;
        this.to = to;
    }

    public DeliveryStatus from() {
        return from;
    }

    public DeliveryStatus to() {
        return to;
    }
}
