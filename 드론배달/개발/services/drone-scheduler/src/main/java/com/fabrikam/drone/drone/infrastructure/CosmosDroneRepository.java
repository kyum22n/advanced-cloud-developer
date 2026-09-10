package com.fabrikam.drone.drone.infrastructure;

import com.fabrikam.drone.contract.vo.DroneStatus;
import com.fabrikam.drone.drone.domain.Drone;
import com.fabrikam.drone.drone.domain.DroneId;
import com.fabrikam.drone.drone.domain.DroneRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * 드론 저장소 구현 — Cosmos DB(진실) + Redis 집합(힌트).
 *
 * <h2>왜 두 저장소를 쓰는가</h2>
 * «가용 드론 검색»은 Cosmos DB 에서 교차 파티션 쿼리가 되어 비싸다.
 * 그래서 가용 드론 ID 를 Redis 집합에 <b>구체화된 뷰</b>로 유지한다.
 *
 * <p>⚠️ Redis 집합은 <b>힌트</b>일 뿐이다. 조회와 할당 사이에 다른 요청이 가져갈 수 있다.
 * <b>최종 확정은 언제나 Cosmos DB 의 조건부 쓰기</b>다. 뷰가 틀려도 불변식은 깨지지 않는다.
 */
@Repository
public class CosmosDroneRepository implements DroneRepository {

    private static final Logger log = LoggerFactory.getLogger(CosmosDroneRepository.class);
    private static final String KEY_AVAILABLE = "drone:available";
    private static final String KEY_CAPACITY  = "drone:capacity:%s";

    private final DroneCosmosDao dao;
    private final StringRedisTemplate redis;

    public CosmosDroneRepository(DroneCosmosDao dao, StringRedisTemplate redis) {
        this.dao = dao;
        this.redis = redis;
    }

    @Override
    public Optional<Drone> findById(DroneId id) {
        return dao.findByDroneId(id.value()).map(DroneDocument::toDomain);
    }

    @Override
    public Drone insert(Drone drone) {
        dao.save(DroneDocument.from(drone));
        syncAvailability(drone);
        return drone;
    }

    @Override
    public Drone saveIfMatch(Drone drone, String expectedEtag) {
        try {
            DroneDocument saved = dao.save(DroneDocument.from(drone));
            Drone result = saved.toDomain();
            syncAvailability(result);
            return result;
        } catch (OptimisticLockingFailureException e) {
            // Cosmos DB 가 etag 불일치로 거부했다 — 다른 인스턴스가 먼저 가져갔다.
            log.debug("드론 조건부 쓰기 충돌");
            throw new OptimisticConcurrencyException(drone.id());
        }
    }

    @Override
    public List<DroneId> findAvailableCandidates(BigDecimal requiredKg, int limit) {
        Set<String> ids = redis.opsForSet().members(KEY_AVAILABLE);
        if (ids == null || ids.isEmpty()) {
            return List.of();
        }
        return ids.stream()
                .filter(id -> hasCapacity(id, requiredKg))
                .limit(limit)
                .map(DroneId::of)
                .toList();
    }

    private boolean hasCapacity(String droneId, BigDecimal requiredKg) {
        if (requiredKg == null) {
            return true;
        }
        String cap = redis.opsForValue().get(KEY_CAPACITY.formatted(droneId));
        if (cap == null) {
            return true;                       // 정보가 없으면 후보에 남긴다 — 최종 확정에서 걸러진다
        }
        try {
            return new BigDecimal(cap).compareTo(requiredKg) >= 0;
        } catch (NumberFormatException e) {
            return true;
        }
    }

    /** 구체화된 뷰 갱신 — 진실(Cosmos)을 쓴 뒤에만 호출한다. */
    private void syncAvailability(Drone drone) {
        String id = drone.id().value();
        if (drone.status() == DroneStatus.AVAILABLE) {
            redis.opsForSet().add(KEY_AVAILABLE, id);
            redis.opsForValue().set(KEY_CAPACITY.formatted(id), drone.capacityKg().toPlainString());
        } else {
            redis.opsForSet().remove(KEY_AVAILABLE, id);
        }
    }
}
