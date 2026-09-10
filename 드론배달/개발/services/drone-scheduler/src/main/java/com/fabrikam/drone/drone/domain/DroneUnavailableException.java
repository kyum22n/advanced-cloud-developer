package com.fabrikam.drone.drone.domain;

/** INV-03 위반 — 이미 다른 배달을 수행 중인 드론에 할당을 시도했다. HTTP 409. */
public class DroneUnavailableException extends RuntimeException {

    private final String droneId;
    private final String currentDeliveryId;

    public DroneUnavailableException(String droneId, String currentDeliveryId) {
        super("드론 %s 는 이미 배달 %s 를 수행 중입니다.".formatted(droneId, currentDeliveryId));
        this.droneId = droneId;
        this.currentDeliveryId = currentDeliveryId;
    }

    public String droneId() {
        return droneId;
    }

    public String currentDeliveryId() {
        return currentDeliveryId;
    }
}
