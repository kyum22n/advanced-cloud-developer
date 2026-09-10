package com.fabrikam.drone.delivery.infrastructure;

import com.fabrikam.drone.contract.vo.DeliveryStatus;
import com.fabrikam.drone.contract.vo.Eta;
import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.contract.vo.TimeWindow;
import com.fabrikam.drone.delivery.domain.Confirmation;
import com.fabrikam.drone.delivery.domain.Delivery;
import com.fabrikam.drone.delivery.domain.DeliveryId;
import com.fabrikam.drone.delivery.domain.Notification;
import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;
import java.util.List;

/**
 * 영속화 표현 — 도메인 모델과 저장 형식을 분리한다.
 *
 * <p>도메인 클래스에 직접 Jackson 어노테이션을 달면, 저장 형식이 바뀔 때마다 도메인이 흔들린다.
 * 변환 레코드를 하나 두는 비용으로 도메인의 순수성을 지킨다.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record DeliveryRecord(
        String deliveryId,
        String ownerId,
        String packageId,
        Location pickup,
        Location dropoff,
        TimeWindow pickupWindow,
        Instant createdAt,
        String droneId,
        DeliveryStatus status,
        Eta eta,
        Location currentLocation,
        Instant updatedAt,
        long version,
        Confirmation confirmation,
        List<Notification> notifications) {

    public static DeliveryRecord from(Delivery d) {
        return new DeliveryRecord(
                d.id().value(), d.ownerId(), d.packageId(),
                d.pickup(), d.dropoff(), d.pickupWindow(), d.createdAt(),
                d.droneId(), d.status(), d.eta(), d.currentLocation(),
                d.updatedAt(), d.version(),
                d.confirmation().orElse(null), d.notifications());
    }

    public Delivery toDomain() {
        return Delivery.restore(DeliveryId.of(deliveryId), ownerId, packageId,
                pickup, dropoff, pickupWindow, createdAt, droneId, status, eta,
                currentLocation, updatedAt, version, confirmation, notifications);
    }

    /** 추적 API 전용 경량 뷰 — 필요한 필드만. 구체화된 뷰 패턴. */
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public record StatusView(String deliveryId,
                             DeliveryStatus status,
                             Location droneLocation,
                             Eta eta,
                             Instant updatedAt) {
    }

    public static StatusView statusViewOf(Delivery d) {
        return new StatusView(d.id().value(), d.status(), d.currentLocation(),
                d.eta(), d.updatedAt());
    }
}
