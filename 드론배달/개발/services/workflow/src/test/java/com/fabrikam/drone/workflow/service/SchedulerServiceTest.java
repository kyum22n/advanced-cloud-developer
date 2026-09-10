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
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Saga 오케스트레이션 테스트.
 *
 * <p>인수 조건 AC-5(타사 위탁)·AC-6(보상 트랜잭션)에 대응한다.
 */
@DisplayName("SchedulerService — Saga 오케스트레이션")
class SchedulerServiceTest {

    private static final Instant NOW = Instant.parse("2026-08-29T10:00:00Z");

    private FakeAgents.CallLog callLog;
    private FakeAccountAgent account;
    private FakePackageAgent pkg;
    private FakeDroneAgent drone;
    private FakeDeliveryAgent delivery;
    private FakeThirdParty thirdParty;
    private InMemorySagaStates sagaStates;
    private SchedulerService scheduler;

    @BeforeEach
    void setUp() {
        callLog = new FakeAgents.CallLog();
        account = new FakeAccountAgent(callLog);
        pkg = new FakePackageAgent(callLog);
        drone = new FakeDroneAgent(callLog);
        delivery = new FakeDeliveryAgent(callLog);
        thirdParty = new FakeThirdParty(callLog);
        sagaStates = new InMemorySagaStates();
        scheduler = new SchedulerService(account, pkg, drone, delivery, thirdParty,
                sagaStates, new WorkflowMetrics(new SimpleMeterRegistry()),
                Clock.fixed(NOW, ZoneOffset.UTC));
    }

    private DeliveryRequestMessage request() {
        return new DeliveryRequestMessage(
                "dlv-0001", "acc-0001", "pkg-0001",
                Location.ofGround(37.5665, 126.9780),
                Location.ofGround(37.5172, 127.0473),
                new TimeWindow(NOW.plusSeconds(600), NOW.plusSeconds(3600)),
                PackageWeight.ofKilograms("2.5"), PackageSize.SMALL,
                "서류 봉투", "req-test-0001");
    }

    @Nested
    @DisplayName("정상 경로")
    class HappyPath {

        @Test
        @DisplayName("네 단계를 순서대로 수행하고 성공한다")
        void executesAllSteps() {
            SagaState saga = scheduler.execute(request());

            assertEquals(SagaState.SagaStatus.SUCCEEDED, saga.status());
            assertEquals(List.of("account.isActive", "package.register", "drone.assign",
                            "delivery.create", "delivery.assignDrone"),
                    callLog.calls());
        }

        @Test
        @DisplayName("완료된 단계가 모두 기록된다 — 보상의 근거")
        void recordsCompletedSteps() {
            SagaState saga = scheduler.execute(request());
            assertTrue(saga.completedSteps().containsAll(List.of(
                    SagaStep.ACCOUNT_VALIDATED, SagaStep.PACKAGE_REGISTERED,
                    SagaStep.DRONE_ASSIGNED, SagaStep.DELIVERY_CREATED)));
        }

        @Test
        @DisplayName("이미 성공한 배달은 다시 처리하지 않는다 — 큐 재전달 멱등성")
        void idempotentOnRedelivery() {
            scheduler.execute(request());
            callLog.clear();

            SagaState again = scheduler.execute(request());
            assertEquals(SagaState.SagaStatus.SUCCEEDED, again.status());
            assertTrue(callLog.calls().isEmpty(), "재전달 시 아무 서비스도 호출하지 않아야 합니다");
        }
    }

    @Nested
    @DisplayName("AC-5 — 가용 드론이 없으면 타사 운송으로 위탁한다")
    class ThirdPartyFallback {

        @Test
        @DisplayName("드론 할당이 비면 타사에 위탁한다")
        void delegatesWhenNoDrone() {
            drone.assignResult = Optional.empty();

            SagaState saga = scheduler.execute(request());

            assertEquals(SagaState.SagaStatus.SUCCEEDED, saga.status());
            assertTrue(callLog.contains("thirdparty.delegate"));
            assertTrue(callLog.contains("delivery.delegate"));
            assertFalse(callLog.contains("delivery.assignDrone"));
        }

        @Test
        @DisplayName("타사 위탁까지 실패하면 보상이 실행된다")
        void compensatesWhenThirdPartyFails() {
            drone.assignResult = Optional.empty();
            thirdParty.result = Optional.empty();

            SagaState saga = scheduler.execute(request());

            assertEquals(SagaState.SagaStatus.COMPENSATED, saga.status());
            assertTrue(callLog.contains("package.delete"), "등록한 패키지를 되돌려야 합니다");
        }
    }

    @Nested
    @DisplayName("AC-6 — 실패 시 보상 트랜잭션이 역순으로 실행된다")
    class Compensation {

        @Test
        @DisplayName("배달 생성이 실패하면 드론 해제 → 패키지 삭제 순으로 되돌린다")
        void compensatesInReverseOrder() {
            delivery.failOnCreate = true;

            SagaState saga = scheduler.execute(request());

            assertEquals(SagaState.SagaStatus.COMPENSATED, saga.status());
            assertTrue(callLog.contains("drone.release"));
            assertTrue(callLog.contains("package.delete"));
            assertTrue(callLog.indexOf("drone.release") < callLog.indexOf("package.delete"),
                    "나중에 만든 것을 먼저 되돌려야 합니다 (역순 보상)");
        }

        @Test
        @DisplayName("패키지 등록이 실패하면 되돌릴 것이 없다 — 읽기 전용 단계는 보상 대상이 아니다")
        void noCompensationWhenNothingCreated() {
            pkg.failOnRegister = true;

            SagaState saga = scheduler.execute(request());

            assertEquals(SagaState.SagaStatus.COMPENSATED, saga.status());
            assertFalse(callLog.contains("drone.release"));
            assertFalse(callLog.contains("package.delete"));
        }

        @Test
        @DisplayName("계정이 비활성이면 즉시 실패하고 아무것도 만들지 않는다")
        void stopsAtInactiveAccount() {
            account.active = false;

            SagaState saga = scheduler.execute(request());

            assertEquals(SagaState.SagaStatus.COMPENSATED, saga.status());
            assertFalse(callLog.contains("package.register"));
            assertFalse(callLog.contains("drone.assign"));
        }

        @Test
        @DisplayName("보상 완료 후 배달을 실패 상태로 표시한다 — 사용자가 알아야 한다")
        void marksDeliveryFailed() {
            delivery.failOnCreate = true;
            scheduler.execute(request());
            assertTrue(callLog.contains("delivery.markFailed"));
        }

        @Test
        @DisplayName("보상 자체가 실패하면 조용히 넘어가지 않는다")
        void doesNotSwallowCompensationFailure() {
            delivery.failOnCreate = true;
            pkg.failOnDelete = true;

            SagaState saga = scheduler.execute(request());

            // 보상이 완전히 성공하지 못했으므로 COMPENSATED 가 아니다.
            assertNotEquals(SagaState.SagaStatus.COMPENSATED, saga.status(),
                    "보상 실패를 성공으로 기록하면 데이터가 조용히 어긋난 채 남는다");
        }
    }

    @Test
    @DisplayName("보상 단계 목록은 역순이고 읽기 전용 단계를 제외한다")
    void stepsToCompensateIsReverseAndFiltered() {
        SagaState saga = new SagaState("dlv-0001", "req-1", NOW);
        saga.complete(SagaStep.ACCOUNT_VALIDATED, NOW);
        saga.complete(SagaStep.PACKAGE_REGISTERED, NOW);
        saga.complete(SagaStep.DRONE_ASSIGNED, NOW);

        assertEquals(List.of(SagaStep.DRONE_ASSIGNED, SagaStep.PACKAGE_REGISTERED),
                saga.stepsToCompensate());
    }
}
