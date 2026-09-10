package com.fabrikam.drone.delivery.domain;

/** 배달 식별자 — 타입으로 감싸 «String 아무거나»가 들어오는 것을 막는다. */
public record DeliveryId(String value) {
    public DeliveryId {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("배달 ID 는 비어 있을 수 없습니다.");
        }
    }

    public static DeliveryId of(String value) {
        return new DeliveryId(value);
    }

    @Override
    public String toString() {
        return value;
    }
}
