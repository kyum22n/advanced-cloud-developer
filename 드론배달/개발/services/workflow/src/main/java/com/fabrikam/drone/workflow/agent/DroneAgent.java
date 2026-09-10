package com.fabrikam.drone.workflow.agent;

import java.math.BigDecimal;
import java.util.Optional;

/** 드론 서비스 에이전트 — 포트. */
public interface DroneAgent {

    /**
     * 드론을 할당한다 (멱등 · PUT).
     *
     * @return 할당된 드론 ID. 가용 드론이 없으면 {@link Optional#empty()}
     *         — 예외가 아니라 «정상적인 결과의 한 종류»다. Workflow 가 타사 위탁으로 전환한다.
     */
    Optional<String> assign(String deliveryId, BigDecimal requiredKg, String correlationId);

    /** 보상 — 할당을 해제한다. 이미 해제되어 있어도 성공으로 본다. */
    void release(String deliveryId, String correlationId);
}
