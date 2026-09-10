package com.fabrikam.drone.contract.vo;

/** 드론 상태 — 값 개체(열거). */
public enum DroneStatus {
    /** 대기 — 할당 가능 */
    AVAILABLE,
    /** 배달 수행 중 — 할당 불가 (INV-03) */
    ASSIGNED,
    /** 충전 중 */
    CHARGING,
    /** 정비 중 */
    MAINTENANCE,
    /** 사용 중지 */
    RETIRED;

    public boolean isAssignable() {
        return this == AVAILABLE;
    }
}
