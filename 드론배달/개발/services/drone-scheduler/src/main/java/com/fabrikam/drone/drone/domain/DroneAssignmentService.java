package com.fabrikam.drone.drone.domain;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

/**
 * 드론 할당 — 도메인 서비스.
 *
 * <p>«어느 드론을 고를 것인가»는 특정 드론의 책임이 아니므로 도메인 서비스다.
 *
 * <h2>경합 처리</h2>
 * 후보 목록은 힌트일 뿐이므로, 하나씩 시도하며 «조건부 쓰기에 성공한 첫 드론»을 쓴다.
 * 이것이 분산 잠금 없이 INV-03 을 지키는 방법이다 — 잠금 서비스는 새로운 단일 실패 지점이 된다.
 */
public class DroneAssignmentService {

    private static final Logger log = LoggerFactory.getLogger(DroneAssignmentService.class);

    /** 후보를 몇 개까지 시도할지. 너무 크면 지연이 늘고, 너무 작으면 경합 시 실패한다. */
    private static final int CANDIDATE_LIMIT = 5;

    private final DroneRepository repository;

    public DroneAssignmentService(DroneRepository repository) {
        this.repository = repository;
    }

    /**
     * 조건에 맞는 드론을 하나 할당한다.
     *
     * @throws NoAvailableDroneException 후보를 모두 시도했지만 성공하지 못했을 때
     */
    public Drone assign(String deliveryId, BigDecimal requiredKg,
                        String correlationId, Instant now) {
        List<DroneId> candidates = repository.findAvailableCandidates(requiredKg, CANDIDATE_LIMIT);
        if (candidates.isEmpty()) {
            throw new NoAvailableDroneException(requiredKg);
        }

        for (DroneId candidate : candidates) {
            var found = repository.findById(candidate);
            if (found.isEmpty()) {
                continue;                                  // 힌트가 오래됐다
            }
            Drone drone = found.get();
            if (!drone.canCarry(requiredKg)) {
                continue;                                  // 상태가 그사이 바뀌었다
            }
            try {
                drone.assign(deliveryId, requiredKg, correlationId, now);
                return repository.saveIfMatch(drone, drone.etag());   // ★ 여기서 경합이 해소된다
            } catch (DroneRepository.OptimisticConcurrencyException e) {
                log.debug("드론 경합 — 다음 후보로 넘어갑니다");
            } catch (DroneUnavailableException e) {
                log.debug("후보가 이미 점유됨 — 다음 후보로 넘어갑니다");
            }
        }
        throw new NoAvailableDroneException(requiredKg);
    }
}
