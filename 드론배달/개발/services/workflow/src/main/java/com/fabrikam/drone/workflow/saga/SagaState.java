package com.fabrikam.drone.workflow.saga;

import java.time.Instant;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;

/**
 * Saga 진행 상태.
 *
 * <p>이 기록이 없으면 Supervisor 는 «어디까지 갔는지» 알 수 없고, 따라서 보상할 수 없다.
 * Saga 오케스트레이션에서 <b>진행 상태의 영속화는 선택이 아니라 필수</b>다.
 */
public class SagaState {

    private final String deliveryId;
    private final String correlationId;
    private final Instant startedAt;

    private final Set<SagaStep> completedSteps = EnumSet.noneOf(SagaStep.class);
    private SagaStatus status;
    private Instant updatedAt;
    private String failureReason;
    private int compensationAttempts;

    /** 단계별 산출물 — 보상 시 필요한 ID 들. */
    private String packageId;
    private String droneId;

    public SagaState(String deliveryId, String correlationId, Instant startedAt) {
        this.deliveryId = deliveryId;
        this.correlationId = correlationId;
        this.startedAt = startedAt;
        this.updatedAt = startedAt;
        this.status = SagaStatus.RUNNING;
    }

    public void complete(SagaStep step, Instant now) {
        completedSteps.add(step);
        this.updatedAt = now;
    }

    public void succeed(Instant now) {
        this.status = SagaStatus.SUCCEEDED;
        this.updatedAt = now;
    }

    public void fail(String reason, Instant now) {
        this.status = SagaStatus.FAILED;
        this.failureReason = reason;
        this.updatedAt = now;
    }

    public void startCompensation(Instant now) {
        this.status = SagaStatus.COMPENSATING;
        this.compensationAttempts++;
        this.updatedAt = now;
    }

    public void compensated(Instant now) {
        this.status = SagaStatus.COMPENSATED;
        this.updatedAt = now;
    }

    public void needsManualIntervention(Instant now) {
        this.status = SagaStatus.MANUAL_INTERVENTION;
        this.updatedAt = now;
    }

    /**
     * 보상해야 할 단계를 <b>역순</b>으로 돌려준다.
     *
     * <p>역순인 이유 — 나중에 만든 것을 먼저 지워야 참조 무결성이 깨지지 않는다.
     * 배달을 지우기 전에 드론을 해제하면, 잠시 «드론 없는 배달»이 존재하게 된다.
     */
    public List<SagaStep> stepsToCompensate() {
        List<SagaStep> out = new ArrayList<>();
        SagaStep[] all = SagaStep.values();
        for (int i = all.length - 1; i >= 0; i--) {
            if (completedSteps.contains(all[i]) && all[i].isCompensable()) {
                out.add(all[i]);
            }
        }
        return out;
    }

    /** 시작 후 지정 시간이 지났는데 아직 진행 중인가 — Supervisor 의 판단 기준. */
    public boolean isStalled(Instant now, java.time.Duration timeout) {
        return status == SagaStatus.RUNNING
                && java.time.Duration.between(startedAt, now).compareTo(timeout) > 0;
    }

    public String deliveryId()              { return deliveryId; }
    public String correlationId()           { return correlationId; }
    public Instant startedAt()              { return startedAt; }
    public Instant updatedAt()              { return updatedAt; }
    public SagaStatus status()              { return status; }
    public String failureReason()           { return failureReason; }
    public int compensationAttempts()       { return compensationAttempts; }
    public Set<SagaStep> completedSteps()   { return EnumSet.copyOf(completedSteps.isEmpty()
                                                    ? EnumSet.noneOf(SagaStep.class)
                                                    : completedSteps); }
    public String packageId()               { return packageId; }
    public void setPackageId(String v)      { this.packageId = v; }
    public String droneId()                 { return droneId; }
    public void setDroneId(String v)        { this.droneId = v; }

    public enum SagaStatus {
        RUNNING, SUCCEEDED, FAILED, COMPENSATING, COMPENSATED, MANUAL_INTERVENTION
    }
}
