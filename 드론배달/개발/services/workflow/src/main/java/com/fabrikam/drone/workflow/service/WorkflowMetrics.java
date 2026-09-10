package com.fabrikam.drone.workflow.service;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

/**
 * Workflow 도메인 메트릭.
 *
 * <p>«어느 단계에서 보상이 발생하는가»를 알아야 원인을 좁힐 수 있다.
 * 보상 총계만 세면 «드론이 부족한 것»과 «패키지 서비스가 깨진 것»을 구분할 수 없다.
 */
@Component
public class WorkflowMetrics {

    private final MeterRegistry registry;
    private final Counter sagaSucceeded;
    private final Counter delegated;
    private final Counter manualIntervention;
    private final Counter stalled;

    public WorkflowMetrics(MeterRegistry registry) {
        this.registry = registry;
        this.sagaSucceeded = Counter.builder("drone.saga.succeeded")
                .description("성공한 Saga 수").register(registry);
        this.delegated = Counter.builder("drone.thirdparty.delegated")
                .description("타사 위탁 건수 — 드론 가동률의 반대 지표").register(registry);
        this.manualIntervention = Counter.builder("drone.saga.manual_intervention")
                .description("수동 개입이 필요한 Saga 수").register(registry);
        this.stalled = Counter.builder("drone.saga.stalled")
                .description("Supervisor 가 감지한 시간 초과 Saga 수").register(registry);
    }

    public void sagaSucceeded()             { sagaSucceeded.increment(); }
    public void delegatedToThirdParty()     { delegated.increment(); }
    public void manualInterventionRequired(){ manualIntervention.increment(); }
    public void stalledDetected(int count)  { stalled.increment(count); }

    /** 보상은 «단계»별로 센다. */
    public void compensated(String step) {
        Counter.builder("drone.saga.compensated")
                .description("보상된 Saga 단계 수")
                .tag("step", step)
                .register(registry)
                .increment();
    }

    /** 드론 할당 거부는 «이유»별로 센다. */
    public void assignmentRejected(String reason) {
        Counter.builder("drone.assignment.rejected")
                .description("드론 할당 거부 건수")
                .tag("reason", reason)
                .register(registry)
                .increment();
    }
}
