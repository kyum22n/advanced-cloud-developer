package com.fabrikam.drone.workflow.agent;

import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.contract.vo.TimeWindow;

/** 배달 서비스 에이전트 — 포트. */
public interface DeliveryAgent {

    /** 배달을 생성한다 (멱등 · PUT). */
    void create(String deliveryId, String ownerId, String packageId,
                Location pickup, Location dropoff, TimeWindow window, String correlationId);

    void assignDrone(String deliveryId, String droneId, String correlationId);

    void delegateToThirdParty(String deliveryId, String externalTrackingId, String correlationId);

    void markFailed(String deliveryId, String reason, String correlationId);

    /** 보상 — 배달을 삭제한다. 이미 없어도 성공으로 본다. */
    void delete(String deliveryId, String correlationId);
}
