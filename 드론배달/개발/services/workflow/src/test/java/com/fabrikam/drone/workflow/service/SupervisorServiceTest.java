package com.fabrikam.drone.workflow.service;

import com.fabrikam.drone.contract.vo.*;
import com.fabrikam.drone.workflow.message.DeliveryRequestMessage;
import com.fabrikam.drone.workflow.saga.SagaState;
import com.fabrikam.drone.workflow.saga.SagaStep;
import com.fabrikam.drone.workflow.support.FakeAgents;
import com.fabrikam.drone.workflow.support.FakeAgents.*;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Supervisor 테스트 — «Scheduler 가 죽었을 때 누가 치우는가».
 */
@DisplayName("SupervisorService — 시간 초과 Saga 감시")
class SupervisorServiceTest {

    private static final Instant START = Instant.parse("2026-08-29T10:00:00Z");
    private static final long TIMEOUT_SECONDS = 300;

    private FakeAgents.CallLog callLog;
    private InMemorySagaStates sagaStates;

    @BeforeEach
    void setUp() {
        callLog = new FakeAgents.CallLog();
        sagaStates = new InMemorySagaStates();
    }

    private SupervisorService supervisorAt(Instant now) {
        var metrics = new WorkflowMetrics(new SimpleMeterRegistry());
        var scheduler = new SchedulerService(
                new FakeAccountAgent(callLog), new FakePackageAgent(callLog),
                new FakeDroneAgent(callLog), new FakeDeliveryAgent(callLog),
                new FakeThirdParty(callLog), sagaStates, metrics,
                Clock.fixed(now, ZoneOffset.UTC));
        return new SupervisorService(sagaStates, scheduler, metrics,
                Clock.fixed(now, ZoneOffset.UTC), TIMEOUT_SECONDS);
    }

    /** ③단계까지 진행하고 멈춘 Saga — Scheduler 인스턴스가 죽은 상황을 재현한다. */
    private SagaState stalledSaga() {
        SagaState saga = new SagaState("dlv-0001", "req-1", START);
        saga.complete(SagaStep.ACCOUNT_VALIDATED, START);
        saga.complete(SagaStep.PACKAGE_REGISTERED, START.plusSeconds(2));
        saga.setPackageId("pkg-0001");
        saga.complete(SagaStep.DRONE_ASSIGNED, START.plusSeconds(5));
        saga.setDroneId("drn-0042");
        sagaStates.save(saga);
        return saga;
    }

    @Test
    @DisplayName("시간 초과 전에는 아무 일도 하지 않는다")
    void doesNothingBeforeTimeout() {
        stalledSaga();
        supervisorAt(START.plusSeconds(100)).scanForStalledSagas();

        assertTrue(callLog.calls().isEmpty(), "아직 진행 중일 수 있는 Saga 를 건드리면 안 됩니다");
    }

    @Test
    @DisplayName("시간 초과된 Saga 를 찾아 보상한다")
    void compensatesStalledSaga() {
        stalledSaga();
        supervisorAt(START.plusSeconds(TIMEOUT_SECONDS + 10)).scanForStalledSagas();

        assertTrue(callLog.contains("drone.release"), "할당된 드론을 해제해야 합니다");
        assertTrue(callLog.contains("package.delete"), "등록된 패키지를 삭제해야 합니다");
        assertTrue(callLog.contains("delivery.markFailed"), "사용자가 알 수 있게 실패로 표시해야 합니다");
    }

    @Test
    @DisplayName("보상 후 상태가 COMPENSATED 가 되어 다시 스캔되지 않는다")
    void marksCompensated() {
        stalledSaga();
        Instant later = START.plusSeconds(TIMEOUT_SECONDS + 10);
        supervisorAt(later).scanForStalledSagas();

        SagaState after = sagaStates.findByDeliveryId("dlv-0001").orElseThrow();
        assertEquals(SagaState.SagaStatus.COMPENSATED, after.status());

        callLog.clear();
        supervisorAt(later.plusSeconds(60)).scanForStalledSagas();
        assertTrue(callLog.calls().isEmpty(), "이미 보상한 Saga 를 다시 보상하면 안 됩니다");
    }

    @Test
    @DisplayName("완료된 Saga 는 시간이 지나도 대상이 아니다")
    void ignoresCompletedSaga() {
        SagaState saga = new SagaState("dlv-0002", "req-2", START);
        saga.succeed(START.plusSeconds(10));
        sagaStates.save(saga);

        supervisorAt(START.plusSeconds(TIMEOUT_SECONDS + 100)).scanForStalledSagas();
        assertTrue(callLog.calls().isEmpty());
    }

    @Test
    @DisplayName("보상은 멱등하므로 여러 인스턴스가 동시에 실행해도 안전하다")
    void compensationIsIdempotent() {
        stalledSaga();
        Instant later = START.plusSeconds(TIMEOUT_SECONDS + 10);

        // 두 Supervisor 인스턴스가 동시에 같은 Saga 를 발견한 상황
        supervisorAt(later).scanForStalledSagas();
        int firstRoundCalls = callLog.calls().size();
        supervisorAt(later).scanForStalledSagas();

        assertEquals(firstRoundCalls, callLog.calls().size(),
                "두 번째 스캔에서는 이미 COMPENSATED 라 추가 호출이 없어야 합니다");
    }

    @Test
    @DisplayName("isStalled 는 진행 중인 Saga 에만 참이다")
    void isStalledOnlyForRunning() {
        SagaState running = new SagaState("dlv-A", "r", START);
        assertTrue(running.isStalled(START.plusSeconds(400), java.time.Duration.ofSeconds(300)));

        running.succeed(START.plusSeconds(10));
        assertFalse(running.isStalled(START.plusSeconds(400), java.time.Duration.ofSeconds(300)));
    }
}
