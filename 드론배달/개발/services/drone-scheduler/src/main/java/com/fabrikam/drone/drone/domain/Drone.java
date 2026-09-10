package com.fabrikam.drone.drone.domain;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.contract.event.EventTypes;
import com.fabrikam.drone.contract.vo.DroneStatus;
import com.fabrikam.drone.contract.vo.Location;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * 드론 — 애그리거트 루트.
 *
 * <h2>이 애그리거트가 존재하는 이유</h2>
 * <b>INV-03 — 하나의 드론은 동시에 하나의 배달만 수행한다.</b>
 *
 * <p>이 규칙을 Delivery 애그리거트가 검사하려면 «드론의 점유 상태»를 읽고 써야 하고,
 * 그러면 두 애그리거트가 한 트랜잭션에 묶인다 — 애그리거트 경계 위반이다.
 * 드론이 스스로 자기 점유를 관리해야 한다.
 *
 * <p>동시성은 저장소의 조건부 쓰기(Cosmos DB ETag)로 최종 확정한다.
 * 이 클래스의 검사는 «같은 인스턴스 안에서의 논리적 정합성»을 보장하고,
 * «서로 다른 인스턴스 사이의 경합»은 저장소가 막는다. 둘 다 필요하다.
 */
public class Drone {

    private final DroneId id;
    private final BigDecimal capacityKg;

    private DroneStatus status;
    private Location currentLocation;
    private int batteryPercent;
    private String currentDeliveryId;
    private Instant locationReportedAt;
    private Instant updatedAt;
    private String etag;

    private final transient List<DomainEvent> pendingEvents = new ArrayList<>();

    /** 배달 수행에 필요한 최소 배터리 잔량. */
    public static final int MIN_BATTERY_FOR_ASSIGNMENT = 30;

    private Drone(DroneId id, BigDecimal capacityKg, DroneStatus status,
                  Location location, int batteryPercent, String currentDeliveryId,
                  Instant locationReportedAt, Instant updatedAt, String etag) {
        this.id = id;
        this.capacityKg = capacityKg;
        this.status = status;
        this.currentLocation = location;
        this.batteryPercent = batteryPercent;
        this.currentDeliveryId = currentDeliveryId;
        this.locationReportedAt = locationReportedAt;
        this.updatedAt = updatedAt;
        this.etag = etag;
    }

    public static Drone register(DroneId id, BigDecimal capacityKg, Location base, Instant now) {
        if (capacityKg == null || capacityKg.signum() <= 0) {
            throw new IllegalArgumentException("적재 용량은 0보다 커야 합니다.");
        }
        return new Drone(id, capacityKg, DroneStatus.AVAILABLE, base, 100, null, now, now, null);
    }

    public static Drone restore(DroneId id, BigDecimal capacityKg, DroneStatus status,
                                Location location, int batteryPercent, String currentDeliveryId,
                                Instant locationReportedAt, Instant updatedAt, String etag) {
        return new Drone(id, capacityKg, status, location, batteryPercent,
                currentDeliveryId, locationReportedAt, updatedAt, etag);
    }

    // ─────────────────────────────────────────────── 불변식

    /**
     * 배달을 할당한다.
     *
     * <p><b>INV-03</b> — 이미 배달 중이면 거부한다.
     *
     * <p>같은 배달을 다시 할당하는 것은 성공으로 본다(멱등) — Workflow 의 재시도가
     * «이미 내가 할당한 드론»에서 실패하면 안 되기 때문이다.
     */
    public void assign(String deliveryId, BigDecimal requiredKg, String correlationId, Instant now) {
        if (deliveryId == null || deliveryId.isBlank()) {
            throw new IllegalArgumentException("배달 ID 는 필수입니다.");
        }
        if (deliveryId.equals(currentDeliveryId)) {
            return;                                          // 멱등 — 이미 이 배달에 할당됨
        }
        if (!status.isAssignable()) {
            throw new DroneUnavailableException(id.value(), currentDeliveryId);
        }
        if (batteryPercent < MIN_BATTERY_FOR_ASSIGNMENT) {
            throw new DroneUnavailableException(id.value(), "배터리 부족(" + batteryPercent + "%)");
        }
        if (requiredKg != null && requiredKg.compareTo(capacityKg) > 0) {
            throw new NoAvailableDroneException(requiredKg);
        }

        this.status = DroneStatus.ASSIGNED;
        this.currentDeliveryId = deliveryId;
        touch(now);
        raise(EventTypes.DRONE_ASSIGNED, correlationId, Map.of("deliveryId", deliveryId));
    }

    /**
     * 할당을 해제한다 — 보상 트랜잭션의 정방향 역연산.
     *
     * <p>이미 해제되어 있어도 성공한다 — 보상은 멱등해야 하기 때문이다.
     */
    public void release(String correlationId, Instant now) {
        if (currentDeliveryId == null) {
            return;                                          // 멱등
        }
        String released = currentDeliveryId;
        this.currentDeliveryId = null;
        this.status = batteryPercent < MIN_BATTERY_FOR_ASSIGNMENT
                ? DroneStatus.CHARGING : DroneStatus.AVAILABLE;
        touch(now);
        raise(EventTypes.DRONE_STATUS_CHANGED, correlationId,
                Map.of("releasedDeliveryId", released, "status", status.name()));
    }

    /** 텔레메트리를 반영한다. */
    public void reportTelemetry(Location location, int batteryPercent,
                                String correlationId, Instant now) {
        if (batteryPercent < 0 || batteryPercent > 100) {
            throw new IllegalArgumentException("배터리 잔량은 0 ~ 100 이어야 합니다: " + batteryPercent);
        }
        this.currentLocation = location;
        this.batteryPercent = batteryPercent;
        this.locationReportedAt = now;

        // 배달 중이 아닌데 배터리가 부족하면 충전 상태로 자동 전환한다.
        if (status == DroneStatus.AVAILABLE && batteryPercent < MIN_BATTERY_FOR_ASSIGNMENT) {
            this.status = DroneStatus.CHARGING;
        }
        touch(now);
        raise(EventTypes.DRONE_STATUS_CHANGED, correlationId, Map.of(
                "status", status.name(),
                "battery", batteryPercent,
                "latitude", location == null ? 0.0 : location.latitude(),
                "longitude", location == null ? 0.0 : location.longitude(),
                "altitude", location == null ? 0.0 : location.altitude(),
                "deliveryId", currentDeliveryId == null ? "" : currentDeliveryId,
                "reportedAt", now.toString()));
    }

    public void enterMaintenance(Instant now) {
        if (status == DroneStatus.ASSIGNED) {
            throw new DroneUnavailableException(id.value(), currentDeliveryId);
        }
        this.status = DroneStatus.MAINTENANCE;
        touch(now);
    }

    public boolean canCarry(BigDecimal weightKg) {
        return status.isAssignable()
                && batteryPercent >= MIN_BATTERY_FOR_ASSIGNMENT
                && (weightKg == null || weightKg.compareTo(capacityKg) <= 0);
    }

    private void touch(Instant now) {
        this.updatedAt = now;
    }

    private void raise(String type, String correlationId, Map<String, Object> data) {
        var payload = new java.util.HashMap<String, Object>(data);
        payload.put("droneId", id.value());
        pendingEvents.add(DomainEvent.of(type, id.value(), correlationId, payload));
    }

    // ─────────────────────────────────────────────── 조회

    public DroneId id()                   { return id; }
    public BigDecimal capacityKg()        { return capacityKg; }
    public DroneStatus status()           { return status; }
    public Location currentLocation()     { return currentLocation; }
    public int batteryPercent()           { return batteryPercent; }
    public Instant locationReportedAt()   { return locationReportedAt; }
    public Instant updatedAt()            { return updatedAt; }
    public String etag()                  { return etag; }
    public Optional<String> currentDeliveryId() { return Optional.ofNullable(currentDeliveryId); }

    public List<DomainEvent> drainEvents() {
        List<DomainEvent> out = List.copyOf(pendingEvents);
        pendingEvents.clear();
        return out;
    }
}
