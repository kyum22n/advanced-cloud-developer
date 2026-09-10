package com.fabrikam.drone.history.domain;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * 배달 이력 — <b>읽기 모델</b>이다. 애그리거트가 아니다.
 *
 * <h2>왜 애그리거트가 아닌가</h2>
 * 이력은 «이미 일어난 일의 기록»이므로 불변식도, 상태 전이도, 커맨드도 없다.
 * 애그리거트로 만들면 없는 규칙을 지키려고 코드가 복잡해진다.
 *
 * <p>이 클래스의 유일한 책임은 «이벤트를 순서대로 받아 조회하기 좋은 형태로 쌓는 것»이다.
 * 그것이 CQRS 읽기 측의 정의다.
 */
public class DeliveryHistoryEntry {

    private final String deliveryId;
    private String ownerId;
    private String packageId;
    private String droneId;
    private String finalStatus;
    private Instant createdAt;
    private Instant completedAt;
    private String failureReason;
    private final List<Milestone> milestones = new ArrayList<>();

    public DeliveryHistoryEntry(String deliveryId) {
        if (deliveryId == null || deliveryId.isBlank()) {
            throw new IllegalArgumentException("배달 ID 는 필수입니다.");
        }
        this.deliveryId = deliveryId;
    }

    /**
     * 이벤트를 반영한다.
     *
     * <p>이벤트가 <b>순서대로 오지 않을 수 있다</b>. Event Hubs 는 파티션 안에서만
     * 순서를 보장하므로, 파티션 키를 deliveryId 로 두어 «같은 배달의 이벤트»는
     * 순서가 유지된다. 그럼에도 방어적으로 «이미 있는 이정표는 덮어쓰지 않는다».
     */
    public void apply(String eventType, Instant occurredAt, java.util.Map<String, Object> data) {
        if (milestones.stream().anyMatch(m -> m.eventType().equals(eventType))) {
            return;                                        // 멱등 — 중복 이벤트 무시
        }
        milestones.add(new Milestone(eventType, occurredAt, str(data, "status")));

        switch (eventType) {
            case "DeliveryCreated" -> {
                this.ownerId = str(data, "ownerId");
                this.packageId = str(data, "packageId");
                this.createdAt = occurredAt;
                this.finalStatus = "PENDING";
            }
            case "DroneAssigned" -> {
                this.droneId = str(data, "droneId");
                this.finalStatus = "SCHEDULED";
            }
            case "DeliveryHeadedToDropoff" -> this.finalStatus = "HEADED_TO_DROPOFF";
            case "DeliveryCompleted" -> {
                this.completedAt = occurredAt;
                this.finalStatus = "COMPLETED";
            }
            case "DeliveryCancelled" -> {
                this.completedAt = occurredAt;
                this.finalStatus = "CANCELLED";
                this.failureReason = str(data, "reason");
            }
            case "DeliveryFailed" -> {
                this.completedAt = occurredAt;
                this.finalStatus = "FAILED";
                this.failureReason = str(data, "reason");
            }
            default -> {
                // 알 수 없는 이벤트 유형 — 이정표로만 남기고 무시한다.
                // 새 이벤트가 추가되어도 이 서비스가 깨지지 않는다 (하위 호환).
            }
        }
    }

    /** 배달 소요 시간(초). 아직 끝나지 않았으면 -1. */
    public long durationSeconds() {
        if (createdAt == null || completedAt == null) {
            return -1;
        }
        return java.time.Duration.between(createdAt, completedAt).getSeconds();
    }

    public boolean isFinished() {
        return completedAt != null;
    }

    private static String str(java.util.Map<String, Object> data, String key) {
        Object v = data == null ? null : data.get(key);
        return v == null ? null : String.valueOf(v);
    }

    public String deliveryId()          { return deliveryId; }
    public String ownerId()             { return ownerId; }
    public String packageId()           { return packageId; }
    public String droneId()             { return droneId; }
    public String finalStatus()         { return finalStatus; }
    public Instant createdAt()          { return createdAt; }
    public Instant completedAt()        { return completedAt; }
    public String failureReason()       { return failureReason; }
    public List<Milestone> milestones() { return Collections.unmodifiableList(milestones); }

    /** 이정표 — 배달이 거쳐 간 지점. */
    public record Milestone(String eventType, Instant occurredAt, String status) {
    }
}
