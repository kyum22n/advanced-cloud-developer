package com.fabrikam.drone.workflow.message;

import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.contract.vo.PackageSize;
import com.fabrikam.drone.contract.vo.PackageWeight;
import com.fabrikam.drone.contract.vo.TimeWindow;

/**
 * 큐로 전달되는 배달 요청.
 *
 * <p>Ingestion 이 만들고 Workflow 가 소비한다. 이 형식이 두 서비스 사이의 계약이다.
 * 필드를 삭제하거나 의미를 바꾸면 배포 순서에 따라 메시지가 깨진다 — <b>필드 추가만</b> 한다.
 */
public record DeliveryRequestMessage(
        String deliveryId,
        String ownerId,
        String packageId,
        Location pickup,
        Location dropoff,
        TimeWindow pickupWindow,
        PackageWeight packageWeight,
        PackageSize packageSize,
        String packageDescription,
        String correlationId) {

    public DeliveryRequestMessage {
        if (deliveryId == null || ownerId == null || packageId == null) {
            throw new IllegalArgumentException("deliveryId · ownerId · packageId 는 필수입니다.");
        }
    }
}
