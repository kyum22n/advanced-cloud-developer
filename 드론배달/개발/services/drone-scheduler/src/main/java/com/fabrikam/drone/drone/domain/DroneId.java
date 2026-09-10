package com.fabrikam.drone.drone.domain;

/** 드론 식별자. */
public record DroneId(String value) {
    public DroneId {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException("드론 ID 는 비어 있을 수 없습니다.");
        }
    }

    public static DroneId of(String value) {
        return new DroneId(value);
    }

    @Override
    public String toString() {
        return value;
    }
}
