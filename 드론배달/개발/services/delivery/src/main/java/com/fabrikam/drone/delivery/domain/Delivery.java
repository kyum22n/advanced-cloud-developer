package com.fabrikam.drone.delivery.domain;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.contract.event.EventTypes;
import com.fabrikam.drone.contract.vo.DeliveryStatus;
import com.fabrikam.drone.contract.vo.Eta;
import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.contract.vo.TimeWindow;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

/**
 * 배달 — 애그리거트 루트.
 *
 * <h2>이 클래스가 지키는 것</h2>
 * <ul>
 *   <li>INV-01 — IN_TRANSIT 이후에는 취소할 수 없다</li>
 *   <li>INV-02 — 드론이 할당되지 않으면 IN_TRANSIT 이 될 수 없다</li>
 *   <li>INV-04 — 종료 상태에서는 어떤 전이도 불가하다</li>
 *   <li>INV-05 — 배달은 반드시 패키지를 참조한다</li>
 *   <li>INV-06 — ETA 는 산출 시점보다 미래다</li>
 * </ul>
 *
 * <h2>설계 규칙</h2>
 * <ul>
 *   <li><b>다른 애그리거트는 ID 로만 참조한다.</b> Package·Drone·Account 객체를 갖지 않는다.
 *       객체로 들고 있으면 배달 하나를 읽는 데 네 곳을 조회하게 되고, 서비스 분리가 불가능해진다.</li>
 *   <li><b>모든 불변식은 이 클래스 안에서 검사한다.</b> 컨트롤러나 서비스가 대신 검사하면
 *       다른 경로로 우회할 수 있는 구멍이 생긴다.</li>
 *   <li><b>프레임워크에 의존하지 않는다.</b> 이 파일에 org.springframework import 가 있으면 규칙 위반이다.</li>
 * </ul>
 */
public class Delivery {

    private final DeliveryId id;
    private final String ownerId;          // Account 애그리거트 — ID 참조
    private final String packageId;        // Package 애그리거트 — ID 참조
    private final Location pickup;
    private final Location dropoff;
    private final TimeWindow pickupWindow;
    private final Instant createdAt;

    private String droneId;                // Drone 애그리거트 — ID 참조
    private DeliveryStatus status;
    private Eta eta;
    private Location currentLocation;
    private Instant updatedAt;
    private long version;

    private Confirmation confirmation;
    private final List<Notification> notifications = new ArrayList<>();

    /** 아직 발행되지 않은 도메인 이벤트. 저장 성공 후 발행한다. */
    private final transient List<DomainEvent> pendingEvents = new ArrayList<>();

    private Delivery(DeliveryId id, String ownerId, String packageId,
                     Location pickup, Location dropoff, TimeWindow pickupWindow,
                     Instant createdAt) {
        this.id = id;
        this.ownerId = ownerId;
        this.packageId = packageId;
        this.pickup = pickup;
        this.dropoff = dropoff;
        this.pickupWindow = pickupWindow;
        this.createdAt = createdAt;
        this.status = DeliveryStatus.PENDING;
        this.updatedAt = createdAt;
        this.version = 0;
    }

    // ───────────────────────────────────────────────── 생성 (팩터리)

    /**
     * 배달을 생성한다.
     *
     * @throws IllegalArgumentException INV-05 위반 — 패키지 참조가 없을 때
     */
    public static Delivery create(DeliveryId id, String ownerId, String packageId,
                                  Location pickup, Location dropoff,
                                  TimeWindow pickupWindow, String correlationId,
                                  Instant now) {
        if (packageId == null || packageId.isBlank()) {
            throw new IllegalArgumentException("INV-05 — 배달은 반드시 패키지를 참조해야 합니다.");
        }
        if (ownerId == null || ownerId.isBlank()) {
            throw new IllegalArgumentException("배달 소유 계정은 필수입니다.");
        }
        if (pickup == null || dropoff == null) {
            throw new IllegalArgumentException("픽업지와 배달지는 필수입니다.");
        }

        Delivery d = new Delivery(id, ownerId, packageId, pickup, dropoff, pickupWindow, now);
        d.raise(EventTypes.DELIVERY_CREATED, correlationId, Map.of(
                "ownerId", ownerId,
                "packageId", packageId,
                "pickup", toMap(pickup),
                "dropoff", toMap(dropoff)));
        return d;
    }

    /** 저장소에서 복원할 때 사용한다. 이벤트를 발생시키지 않는다. */
    public static Delivery restore(DeliveryId id, String ownerId, String packageId,
                                   Location pickup, Location dropoff, TimeWindow pickupWindow,
                                   Instant createdAt, String droneId, DeliveryStatus status,
                                   Eta eta, Location currentLocation, Instant updatedAt,
                                   long version, Confirmation confirmation,
                                   List<Notification> notifications) {
        Delivery d = new Delivery(id, ownerId, packageId, pickup, dropoff, pickupWindow, createdAt);
        d.droneId = droneId;
        d.status = status;
        d.eta = eta;
        d.currentLocation = currentLocation;
        d.updatedAt = updatedAt;
        d.version = version;
        d.confirmation = confirmation;
        if (notifications != null) {
            d.notifications.addAll(notifications);
        }
        return d;
    }

    // ───────────────────────────────────────────────── 상태 전이

    /** 드론을 할당한다 — PENDING → SCHEDULED. */
    public void assignDrone(String droneId, String correlationId, Instant now) {
        if (droneId == null || droneId.isBlank()) {
            throw new IllegalArgumentException("드론 ID 는 필수입니다.");
        }
        transitionTo(DeliveryStatus.SCHEDULED, now);
        this.droneId = droneId;
        raise(EventTypes.DRONE_ASSIGNED, correlationId, Map.of("droneId", droneId));
    }

    /** 타사 운송으로 위탁한다 — PENDING → DELEGATED. */
    public void delegateToThirdParty(String externalTrackingId, String correlationId, Instant now) {
        transitionTo(DeliveryStatus.DELEGATED, now);
        raise(EventTypes.DELIVERY_RESCHEDULED, correlationId,
                Map.of("delegatedTo", "third-party", "externalTrackingId",
                        externalTrackingId == null ? "" : externalTrackingId));
    }

    /**
     * 패키지를 적재하고 이동을 시작한다 — SCHEDULED → IN_TRANSIT.
     *
     * @throws InvalidStateTransitionException INV-02 위반 — 드론이 할당되지 않았을 때
     */
    public void markInTransit(Instant now) {
        if (droneId == null) {
            throw new InvalidStateTransitionException(status, DeliveryStatus.IN_TRANSIT);
        }
        transitionTo(DeliveryStatus.IN_TRANSIT, now);
    }

    /** 배달지로 향한다 — IN_TRANSIT → HEADED_TO_DROPOFF. */
    public void headToDropoff(String correlationId, Instant now) {
        transitionTo(DeliveryStatus.HEADED_TO_DROPOFF, now);
        raise(EventTypes.DELIVERY_HEADED_TO_DROPOFF, correlationId, Map.of(
                "droneId", droneId == null ? "" : droneId,
                "currentLocation", currentLocation == null ? Map.of() : toMap(currentLocation)));
    }

    /** 배달을 완료한다. */
    public void complete(Confirmation confirmation, String correlationId, Instant now) {
        if (confirmation == null) {
            throw new IllegalArgumentException("완료에는 수령 확인이 필요합니다.");
        }
        transitionTo(DeliveryStatus.COMPLETED, now);
        this.confirmation = confirmation;
        raise(EventTypes.DELIVERY_COMPLETED, correlationId, Map.of(
                "completedAt", now.toString(),
                "confirmationId", confirmation.confirmationId()));
    }

    /**
     * 배달을 취소한다.
     *
     * @throws InvalidStateTransitionException INV-01 위반 — IN_TRANSIT 이후일 때
     */
    public void cancel(String reason, String correlationId, Instant now) {
        if (!status.isCancellable()) {
            throw new InvalidStateTransitionException(status, DeliveryStatus.CANCELLED);
        }
        transitionTo(DeliveryStatus.CANCELLED, now);
        raise(EventTypes.DELIVERY_CANCELLED, correlationId,
                Map.of("reason", reason == null ? "" : reason));
    }

    /** 배달이 실패했다. Supervisor 가 보상을 실행한다. */
    public void fail(String reason, String correlationId, Instant now) {
        DeliveryStatus previous = status;
        transitionTo(DeliveryStatus.FAILED, now);
        raise(EventTypes.DELIVERY_FAILED, correlationId, Map.of(
                "reason", reason == null ? "" : reason,
                "lastStatus", previous.name()));
    }

    /** 보상 트랜잭션이 완료됐다 — FAILED → COMPENSATED. */
    public void markCompensated(Instant now) {
        transitionTo(DeliveryStatus.COMPENSATED, now);
    }

    // ───────────────────────────────────────────────── 값 갱신

    /**
     * ETA 를 갱신한다.
     *
     * @throws IllegalArgumentException INV-06 위반 — ETA 가 과거일 때
     */
    public void updateEta(Eta newEta, Instant now) {
        if (newEta == null) {
            throw new IllegalArgumentException("ETA 는 null 일 수 없습니다.");
        }
        if (!newEta.isFuture()) {
            throw new IllegalArgumentException("INV-06 — ETA 는 산출 시점보다 미래여야 합니다.");
        }
        if (status.isTerminal()) {
            throw new InvalidStateTransitionException(status, status);
        }
        this.eta = newEta;
        touch(now);
    }

    /** 드론 위치를 반영한다. 상태 전이는 일으키지 않는다. */
    public void updateLocation(Location location, Instant now) {
        if (status.isTerminal()) {
            return;                                   // 종료된 배달은 위치를 갱신하지 않는다
        }
        this.currentLocation = location;
        touch(now);
    }

    public void recordNotification(String channel, String messageKey, Instant now) {
        notifications.add(new Notification(UUID.randomUUID().toString(), channel, messageKey, now));
        touch(now);
    }

    // ───────────────────────────────────────────────── 내부

    private void transitionTo(DeliveryStatus next, Instant now) {
        if (!status.canTransitionTo(next)) {
            throw new InvalidStateTransitionException(status, next);
        }
        this.status = next;
        touch(now);
    }

    private void touch(Instant now) {
        this.updatedAt = now;
        this.version++;
    }

    private void raise(String type, String correlationId, Map<String, Object> data) {
        Map<String, Object> payload = new HashMap<>(data);
        payload.put("deliveryId", id.value());
        payload.put("status", status.name());
        pendingEvents.add(DomainEvent.of(type, id.value(), correlationId, payload));
    }

    private static Map<String, Object> toMap(Location l) {
        return Map.of("latitude", l.latitude(), "longitude", l.longitude(), "altitude", l.altitude());
    }

    // ───────────────────────────────────────────────── 조회

    public DeliveryId id()                 { return id; }
    public String ownerId()                { return ownerId; }
    public String packageId()              { return packageId; }
    public Location pickup()               { return pickup; }
    public Location dropoff()              { return dropoff; }
    public TimeWindow pickupWindow()       { return pickupWindow; }
    public String droneId()                { return droneId; }
    public DeliveryStatus status()         { return status; }
    public Eta eta()                       { return eta; }
    public Location currentLocation()      { return currentLocation; }
    public Instant createdAt()             { return createdAt; }
    public Instant updatedAt()             { return updatedAt; }
    public long version()                  { return version; }
    public Optional<Confirmation> confirmation() { return Optional.ofNullable(confirmation); }
    public List<Notification> notifications()    { return Collections.unmodifiableList(notifications); }

    /** 발행 대기 중인 이벤트를 꺼내고 비운다. 저장 성공 후 호출한다. */
    public List<DomainEvent> drainEvents() {
        List<DomainEvent> out = List.copyOf(pendingEvents);
        pendingEvents.clear();
        return out;
    }
}
