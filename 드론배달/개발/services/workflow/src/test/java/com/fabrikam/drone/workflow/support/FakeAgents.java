package com.fabrikam.drone.workflow.support;

import com.fabrikam.drone.contract.vo.*;
import com.fabrikam.drone.workflow.agent.*;
import com.fabrikam.drone.workflow.saga.SagaState;
import com.fabrikam.drone.workflow.saga.SagaStateRepository;

import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.*;

/**
 * 테스트용 가짜 에이전트.
 *
 * <p>Saga 의 «보상이 실제로 호출되는가»를 검증하려면 각 호출을 기록해야 한다.
 * 모의 프레임워크 대신 손으로 쓴 가짜를 쓰는 이유 —
 * <b>호출 순서</b>까지 검증해야 하는데, 그게 명시적으로 드러나기 때문이다.
 */
public final class FakeAgents {

    private FakeAgents() {
    }

    /** 모든 호출을 시간 순으로 기록하는 공용 기록장. */
    public static class CallLog {
        private final List<String> calls = new ArrayList<>();

        public void record(String call) {
            calls.add(call);
        }

        public List<String> calls() {
            return List.copyOf(calls);
        }

        public boolean contains(String call) {
            return calls.contains(call);
        }

        public int indexOf(String call) {
            return calls.indexOf(call);
        }

        public void clear() {
            calls.clear();
        }
    }

    public static class FakeAccountAgent implements AccountAgent {
        private final CallLog log;
        public boolean active = true;

        public FakeAccountAgent(CallLog log) {
            this.log = log;
        }

        @Override
        public boolean isActive(String accountId, String correlationId) {
            log.record("account.isActive");
            return active;
        }
    }

    public static class FakePackageAgent implements PackageAgent {
        private final CallLog log;
        public boolean failOnRegister = false;
        public boolean failOnDelete = false;

        public FakePackageAgent(CallLog log) {
            this.log = log;
        }

        @Override
        public String register(String packageId, PackageWeight weight, PackageSize size,
                               String description, String correlationId) {
            log.record("package.register");
            if (failOnRegister) {
                throw new IllegalStateException("패키지 등록 실패 (테스트)");
            }
            return packageId;
        }

        @Override
        public void delete(String packageId, String correlationId) {
            log.record("package.delete");
            if (failOnDelete) {
                throw new IllegalStateException("패키지 삭제 실패 (테스트)");
            }
        }
    }

    public static class FakeDroneAgent implements DroneAgent {
        private final CallLog log;
        public Optional<String> assignResult = Optional.of("drn-0042");

        public FakeDroneAgent(CallLog log) {
            this.log = log;
        }

        @Override
        public Optional<String> assign(String deliveryId, BigDecimal requiredKg,
                                       String correlationId) {
            log.record("drone.assign");
            return assignResult;
        }

        @Override
        public void release(String deliveryId, String correlationId) {
            log.record("drone.release");
        }
    }

    public static class FakeDeliveryAgent implements DeliveryAgent {
        private final CallLog log;
        public boolean failOnCreate = false;

        public FakeDeliveryAgent(CallLog log) {
            this.log = log;
        }

        @Override
        public void create(String deliveryId, String ownerId, String packageId,
                           Location pickup, Location dropoff, TimeWindow window,
                           String correlationId) {
            log.record("delivery.create");
            if (failOnCreate) {
                throw new IllegalStateException("배달 생성 실패 (테스트)");
            }
        }

        @Override
        public void assignDrone(String deliveryId, String droneId, String correlationId) {
            log.record("delivery.assignDrone");
        }

        @Override
        public void delegateToThirdParty(String deliveryId, String externalTrackingId,
                                         String correlationId) {
            log.record("delivery.delegate");
        }

        @Override
        public void markFailed(String deliveryId, String reason, String correlationId) {
            log.record("delivery.markFailed");
        }

        @Override
        public void delete(String deliveryId, String correlationId) {
            log.record("delivery.delete");
        }
    }

    public static class FakeThirdParty implements ThirdPartyTransportPort {
        private final CallLog log;
        public Optional<String> result = Optional.of("TP-99887766");

        public FakeThirdParty(CallLog log) {
            this.log = log;
        }

        @Override
        public Optional<String> delegate(String deliveryId, Location pickup, Location dropoff,
                                         PackageWeight weight, String correlationId) {
            log.record("thirdparty.delegate");
            return result;
        }
    }

    /** 메모리 기반 Saga 상태 저장소. */
    public static class InMemorySagaStates implements SagaStateRepository {
        private final Map<String, SagaState> store = new LinkedHashMap<>();

        @Override
        public void save(SagaState state) {
            store.put(state.deliveryId(), state);
        }

        @Override
        public Optional<SagaState> findByDeliveryId(String deliveryId) {
            return Optional.ofNullable(store.get(deliveryId));
        }

        @Override
        public List<SagaState> findStalled(Instant now, Duration timeout, int limit) {
            return store.values().stream()
                    .filter(s -> s.isStalled(now, timeout))
                    .limit(limit)
                    .toList();
        }

        @Override
        public void delete(String deliveryId) {
            store.remove(deliveryId);
        }

        public Collection<SagaState> all() {
            return store.values();
        }
    }
}
