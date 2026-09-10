package com.fabrikam.drone.drone.domain;

import com.fabrikam.drone.contract.vo.Location;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 할당 도메인 서비스 — 경합 상황 검증.
 *
 * <p>실제 Cosmos DB 없이 «조건부 쓰기가 실패하는 상황»을 가짜 저장소로 재현한다.
 * 이것이 도메인 계층을 인프라에서 분리해 두는 실용적 이익이다.
 */
@DisplayName("DroneAssignmentService — 경합 해소")
class DroneAssignmentServiceTest {

    private static final Instant NOW = Instant.parse("2026-08-29T10:00:00Z");
    private static final Location BASE = Location.ofGround(37.5665, 126.9780);
    private static final String CORR = "req-test";

    private FakeDroneRepository repository;
    private DroneAssignmentService service;

    @BeforeEach
    void setUp() {
        repository = new FakeDroneRepository();
        service = new DroneAssignmentService(repository);
    }

    @Test
    @DisplayName("가용 드론이 있으면 할당된다")
    void assignsAvailableDrone() {
        repository.add(drone("drn-0001", "5.0"));
        Drone assigned = service.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW);
        assertEquals("drn-0001", assigned.id().value());
    }

    @Test
    @DisplayName("가용 드론이 없으면 NoAvailableDroneException 이 난다 — Workflow 가 타사로 전환한다")
    void throwsWhenNoDrone() {
        assertThrows(NoAvailableDroneException.class,
                () -> service.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW));
    }

    @Test
    @DisplayName("첫 후보가 경합에서 지면 다음 후보로 넘어간다")
    void fallsBackOnConflict() {
        repository.add(drone("drn-0001", "5.0"));
        repository.add(drone("drn-0002", "5.0"));
        repository.failOnceFor("drn-0001");                 // 첫 후보는 조건부 쓰기 실패

        Drone assigned = service.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW);
        assertEquals("drn-0002", assigned.id().value(), "경합에 진 뒤 다음 후보를 써야 합니다");
    }

    @Test
    @DisplayName("모든 후보가 경합에서 지면 가용 드론 없음으로 처리한다")
    void throwsWhenAllCandidatesConflict() {
        repository.add(drone("drn-0001", "5.0"));
        repository.add(drone("drn-0002", "5.0"));
        repository.failOnceFor("drn-0001");
        repository.failOnceFor("drn-0002");

        assertThrows(NoAvailableDroneException.class,
                () -> service.assign("dlv-0001", new BigDecimal("2.5"), CORR, NOW));
    }

    @Test
    @DisplayName("용량이 부족한 드론은 후보에서 제외된다")
    void skipsInsufficientCapacity() {
        repository.add(drone("drn-small", "1.0"));
        repository.add(drone("drn-large", "5.0"));

        Drone assigned = service.assign("dlv-0001", new BigDecimal("3.0"), CORR, NOW);
        assertEquals("drn-large", assigned.id().value());
    }

    private static Drone drone(String id, String capacityKg) {
        return Drone.register(DroneId.of(id), new BigDecimal(capacityKg), BASE, NOW);
    }

    /** 조건부 쓰기 실패를 재현할 수 있는 가짜 저장소. */
    private static class FakeDroneRepository implements DroneRepository {

        private final Map<String, Drone> store = new LinkedHashMap<>();
        private final List<String> failOnce = new ArrayList<>();

        void add(Drone d) {
            store.put(d.id().value(), d);
        }

        void failOnceFor(String droneId) {
            failOnce.add(droneId);
        }

        @Override
        public Optional<Drone> findById(DroneId id) {
            return Optional.ofNullable(store.get(id.value()));
        }

        @Override
        public Drone insert(Drone drone) {
            store.put(drone.id().value(), drone);
            return drone;
        }

        @Override
        public Drone saveIfMatch(Drone drone, String expectedEtag) {
            if (failOnce.remove(drone.id().value())) {
                throw new OptimisticConcurrencyException(drone.id());
            }
            store.put(drone.id().value(), drone);
            return drone;
        }

        @Override
        public List<DroneId> findAvailableCandidates(BigDecimal requiredKg, int limit) {
            return store.values().stream()
                    .filter(d -> d.canCarry(requiredKg))
                    .limit(limit)
                    .map(Drone::id)
                    .toList();
        }
    }
}
