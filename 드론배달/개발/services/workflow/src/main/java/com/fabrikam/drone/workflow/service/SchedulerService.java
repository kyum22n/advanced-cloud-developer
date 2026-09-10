package com.fabrikam.drone.workflow.service;

import com.fabrikam.drone.workflow.agent.*;
import com.fabrikam.drone.workflow.message.DeliveryRequestMessage;
import com.fabrikam.drone.workflow.saga.SagaState;
import com.fabrikam.drone.workflow.saga.SagaStateRepository;
import com.fabrikam.drone.workflow.saga.SagaStep;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Instant;
import java.util.Optional;

/**
 * Saga 오케스트레이터 — 스케줄러 에이전트 감독자 패턴의 «스케줄러».
 *
 * <h2>이 클래스가 아는 것과 모르는 것</h2>
 * <ul>
 *   <li><b>안다</b> — 단계의 순서, 실패 시 어디까지 되돌려야 하는지</li>
 *   <li><b>모른다</b> — 각 단계의 «비즈니스 규칙». 그것은 각 서비스의 애그리거트가 판단한다</li>
 * </ul>
 *
 * <p>이 구분이 무너지면 Workflow 가 «분산된 단일체의 중심»이 된다.
 * 판별법 — 이 클래스에 도메인 규칙({@code if (weight > 5)} 같은)이 나타나면 새고 있는 것이다.
 *
 * <h2>안무(Choreography) 를 쓰지 않은 이유</h2>
 * 각 서비스가 이벤트로 연쇄하면 결합도는 낮아지지만, «지금 이 배달이 어느 단계인지»를
 * 아무도 모르게 된다. 배달 예약은 <b>실패 시 반드시 보상</b>해야 하므로 중앙 조정자가 유리하다.
 */
@Service
public class SchedulerService {

    private static final Logger log = LoggerFactory.getLogger(SchedulerService.class);

    private final AccountAgent accountAgent;
    private final PackageAgent packageAgent;
    private final DroneAgent droneAgent;
    private final DeliveryAgent deliveryAgent;
    private final ThirdPartyTransportPort thirdParty;
    private final SagaStateRepository sagaStates;
    private final WorkflowMetrics metrics;
    private final Clock clock;

    public SchedulerService(AccountAgent accountAgent,
                            PackageAgent packageAgent,
                            DroneAgent droneAgent,
                            DeliveryAgent deliveryAgent,
                            ThirdPartyTransportPort thirdParty,
                            SagaStateRepository sagaStates,
                            WorkflowMetrics metrics,
                            Clock clock) {
        this.accountAgent = accountAgent;
        this.packageAgent = packageAgent;
        this.droneAgent = droneAgent;
        this.deliveryAgent = deliveryAgent;
        this.thirdParty = thirdParty;
        this.sagaStates = sagaStates;
        this.metrics = metrics;
        this.clock = clock;
    }

    /**
     * 배달 요청을 처리한다.
     *
     * <p>이미 성공한 배달이면 아무것도 하지 않는다 — 큐 재전달에 대한 <b>멱등 처리</b>.
     */
    public SagaState execute(DeliveryRequestMessage request) {
        MDC.put("deliveryId", request.deliveryId());
        MDC.put("correlationId", request.correlationId());
        try {
            return runSaga(request);
        } finally {
            MDC.remove("deliveryId");
            MDC.remove("correlationId");
        }
    }

    private SagaState runSaga(DeliveryRequestMessage request) {
        Instant now = clock.instant();

        // ── 멱등 — 이미 처리한 배달인가
        Optional<SagaState> existing = sagaStates.findByDeliveryId(request.deliveryId());
        if (existing.isPresent()
                && existing.get().status() == SagaState.SagaStatus.SUCCEEDED) {
            log.info("이미 처리된 배달 요청 — 건너뜁니다");
            return existing.get();
        }

        SagaState saga = new SagaState(request.deliveryId(), request.correlationId(), now);
        sagaStates.save(saga);

        try {
            // ① 계정 검증 — 읽기 전용이므로 보상 대상이 아니다
            if (!accountAgent.isActive(request.ownerId(), request.correlationId())) {
                throw new SagaFailedException("계정이 활성 상태가 아닙니다: account inactive");
            }
            saga.complete(SagaStep.ACCOUNT_VALIDATED, clock.instant());
            sagaStates.save(saga);

            // ② 패키지 등록
            String packageId = packageAgent.register(request.packageId(),
                    request.packageWeight(), request.packageSize(),
                    request.packageDescription(), request.correlationId());
            saga.setPackageId(packageId);
            saga.complete(SagaStep.PACKAGE_REGISTERED, clock.instant());
            sagaStates.save(saga);

            // ③ 드론 할당 — 실패는 «예외»가 아니라 «분기»다
            Optional<String> droneId = droneAgent.assign(request.deliveryId(),
                    request.packageWeight() == null ? null : request.packageWeight().toKilograms(),
                    request.correlationId());

            if (droneId.isPresent()) {
                saga.setDroneId(droneId.get());
                saga.complete(SagaStep.DRONE_ASSIGNED, clock.instant());
                sagaStates.save(saga);

                // ④ 배달 생성
                createDelivery(request);
                deliveryAgent.assignDrone(request.deliveryId(), droneId.get(),
                        request.correlationId());
            } else {
                // 가용 드론 없음 → 타사 위탁 (POL-03)
                metrics.assignmentRejected("no_drone");
                createDelivery(request);
                Optional<String> tracking = thirdParty.delegate(request.deliveryId(),
                        request.pickup(), request.dropoff(),
                        request.packageWeight(), request.correlationId());
                if (tracking.isEmpty()) {
                    throw new SagaFailedException("타사 위탁에 실패했습니다: thirdparty unavailable");
                }
                deliveryAgent.delegateToThirdParty(request.deliveryId(), tracking.get(),
                        request.correlationId());
                metrics.delegatedToThirdParty();
            }
            saga.complete(SagaStep.DELIVERY_CREATED, clock.instant());

            saga.succeed(clock.instant());
            sagaStates.save(saga);
            metrics.sagaSucceeded();
            log.info("배달 요청 처리 완료");
            return saga;

        } catch (RuntimeException e) {
            log.warn("배달 처리 실패 — 보상을 실행합니다: {}", e.getMessage());
            saga.fail(e.getMessage(), clock.instant());
            sagaStates.save(saga);
            compensate(saga);
            return saga;
        }
    }

    private void createDelivery(DeliveryRequestMessage r) {
        deliveryAgent.create(r.deliveryId(), r.ownerId(), r.packageId(),
                r.pickup(), r.dropoff(), r.pickupWindow(), r.correlationId());
    }

    /**
     * 보상 트랜잭션 — 완료된 단계를 <b>역순</b>으로 되돌린다.
     *
     * <p>보상 자체가 실패할 수 있다. 그때는 재시도하고, 그래도 안 되면
     * 수동 개입 상태로 표시한다 — <b>조용히 포기하지 않는다</b>.
     */
    public void compensate(SagaState saga) {
        Instant now = clock.instant();
        saga.startCompensation(now);
        sagaStates.save(saga);

        boolean allSucceeded = true;
        for (SagaStep step : saga.stepsToCompensate()) {
            try {
                compensateStep(saga, step);
                metrics.compensated(step.name());
            } catch (RuntimeException e) {
                log.error("보상 실패 — 단계 {}: {}", step, e.getMessage());
                allSucceeded = false;
            }
        }

        if (allSucceeded) {
            deliveryAgent.markFailed(saga.deliveryId(),
                    saga.failureReason() == null ? "처리 실패" : saga.failureReason(),
                    saga.correlationId());
            saga.compensated(clock.instant());
        } else if (saga.compensationAttempts() >= MAX_COMPENSATION_ATTEMPTS) {
            // 3회를 넘기면 사람이 봐야 한다. 무한 재시도는 문제를 감춘다.
            log.error("보상 재시도 한도 초과 — 수동 개입이 필요합니다");
            saga.needsManualIntervention(clock.instant());
            metrics.manualInterventionRequired();
        }
        sagaStates.save(saga);
    }

    private void compensateStep(SagaState saga, SagaStep step) {
        switch (step) {
            case DELIVERY_CREATED ->
                    deliveryAgent.delete(saga.deliveryId(), saga.correlationId());
            case DRONE_ASSIGNED ->
                    droneAgent.release(saga.deliveryId(), saga.correlationId());
            case PACKAGE_REGISTERED -> {
                if (saga.packageId() != null) {
                    packageAgent.delete(saga.packageId(), saga.correlationId());
                }
            }
            case ACCOUNT_VALIDATED -> {
                // 읽기 전용 — 되돌릴 것이 없다
            }
        }
    }

    public static final int MAX_COMPENSATION_ATTEMPTS = 3;

    /** Saga 진행 중 발생한 복구 불가 실패. */
    public static class SagaFailedException extends RuntimeException {
        public SagaFailedException(String message) {
            super(message);
        }
    }
}
