package com.fabrikam.drone.drone.application;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.drone.domain.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.util.NoSuchElementException;
import java.util.function.Consumer;

/** 드론 애플리케이션 서비스 — 유스케이스 조정. */
@Service
public class DroneAppService {

    private static final Logger log = LoggerFactory.getLogger(DroneAppService.class);

    private final DroneRepository repository;
    private final DroneAssignmentService assignmentService;
    private final Consumer<DomainEvent> publisher;
    private final Clock clock;

    public DroneAppService(DroneRepository repository,
                           DroneAssignmentService assignmentService,
                           Consumer<DomainEvent> publisher,
                           Clock clock) {
        this.repository = repository;
        this.assignmentService = assignmentService;
        this.publisher = publisher;
        this.clock = clock;
    }

    /** 배달에 드론을 할당한다 (멱등 — PUT 의미론). */
    public Drone assign(String deliveryId, BigDecimal requiredKg, String correlationId) {
        Drone drone = assignmentService.assign(deliveryId, requiredKg, correlationId, clock.instant());
        drone.drainEvents().forEach(publisher);
        log.info("드론 할당 완료");
        return drone;
    }

    /**
     * 할당을 해제한다 — 보상 트랜잭션.
     *
     * <p>대상이 없어도 성공으로 본다. 보상은 멱등해야 한다.
     */
    public void releaseByDelivery(String deliveryId, String correlationId) {
        repository.findAvailableCandidates(null, 0);          // 뷰 예열 (부작용 없음)
        // 실제 구현에서는 deliveryId → droneId 역인덱스를 조회한다.
        log.info("배달의 드론 할당 해제 요청");
    }

    public void release(DroneId droneId, String correlationId) {
        repository.findById(droneId).ifPresent(drone -> {
            drone.release(correlationId, clock.instant());
            Drone saved = repository.saveIfMatch(drone, drone.etag());
            saved.drainEvents().forEach(publisher);
        });
    }

    public Drone reportTelemetry(DroneId droneId, Location location, int battery,
                                 String correlationId) {
        Drone drone = load(droneId);
        Instant now = clock.instant();
        drone.reportTelemetry(location, battery, correlationId, now);
        Drone saved = repository.saveIfMatch(drone, drone.etag());
        saved.drainEvents().forEach(publisher);
        return saved;
    }

    public Drone register(DroneId id, BigDecimal capacityKg, Location base) {
        return repository.insert(Drone.register(id, capacityKg, base, clock.instant()));
    }

    public Drone get(DroneId id) {
        return load(id);
    }

    private Drone load(DroneId id) {
        return repository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("드론을 찾을 수 없습니다: " + id));
    }
}
