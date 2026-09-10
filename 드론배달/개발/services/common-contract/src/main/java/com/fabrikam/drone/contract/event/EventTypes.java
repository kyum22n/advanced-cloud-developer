package com.fabrikam.drone.contract.event;

/**
 * 도메인 이벤트 유형 — 게시된 언어의 어휘.
 *
 * <p>문자열 리터럴을 코드 여기저기에 흩뿌리면 오타 하나로 이벤트가 사라진다.
 * 상수로 모아 두면 컴파일러가 오타를 잡고, 어떤 이벤트가 있는지 한눈에 보인다.
 */
public final class EventTypes {

    private EventTypes() {
    }

    // ── DeliveryTracking 그룹 — 구독자: Delivery History · 알림 · 청구서 · 콜 센터
    public static final String DELIVERY_CREATED            = "DeliveryCreated";
    public static final String DELIVERY_RESCHEDULED        = "DeliveryRescheduled";
    public static final String DELIVERY_HEADED_TO_DROPOFF  = "DeliveryHeadedToDropoff";
    public static final String DELIVERY_COMPLETED          = "DeliveryCompleted";
    public static final String DELIVERY_CANCELLED          = "DeliveryCancelled";
    public static final String DELIVERY_FAILED             = "DeliveryFailed";

    // ── DroneStatus 그룹 — 구독자: Delivery · ETA 분석
    public static final String DRONE_ASSIGNED              = "DroneAssigned";
    public static final String DRONE_ASSIGNMENT_REJECTED   = "DroneAssignmentRejected";
    public static final String DRONE_STATUS_CHANGED        = "DroneStatusChanged";

    // ── Package 그룹
    public static final String PACKAGE_REGISTERED          = "PackageRegistered";

    /** Event Hubs 대상 이름 */
    public static final String HUB_DELIVERY_TRACKING = "delivery-tracking";
    public static final String HUB_DRONE_STATUS      = "drone-status";
}
