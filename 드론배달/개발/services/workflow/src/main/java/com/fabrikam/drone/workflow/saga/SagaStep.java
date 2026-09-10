package com.fabrikam.drone.workflow.saga;

/**
 * Saga 단계.
 *
 * <p>순서가 곧 실행 순서이고, 보상은 <b>역순</b>으로 수행한다.
 * 열거형 순서에 의미를 두므로 중간에 값을 끼워 넣을 때 주의해야 한다.
 */
public enum SagaStep {

    /** ① 계정 검증 — 읽기 전용이므로 보상이 필요 없다. */
    ACCOUNT_VALIDATED(false),

    /** ② 패키지 등록 — 보상: DELETE /packages/{id} */
    PACKAGE_REGISTERED(true),

    /** ③ 드론 할당 — 보상: DELETE /drones/assignments/{deliveryId} */
    DRONE_ASSIGNED(true),

    /** ④ 배달 생성 — 보상: DELETE /deliveries/{id}/compensate */
    DELIVERY_CREATED(true);

    private final boolean compensable;

    SagaStep(boolean compensable) {
        this.compensable = compensable;
    }

    /** 이 단계가 «되돌릴 것»을 남기는가. 읽기 전용 단계는 보상하지 않는다. */
    public boolean isCompensable() {
        return compensable;
    }
}
