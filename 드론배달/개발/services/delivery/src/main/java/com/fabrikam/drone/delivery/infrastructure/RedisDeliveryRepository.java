package com.fabrikam.drone.delivery.infrastructure;

import com.fabrikam.drone.delivery.domain.Delivery;
import com.fabrikam.drone.delivery.domain.DeliveryId;
import com.fabrikam.drone.delivery.domain.DeliveryRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Repository;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * Redis 기반 배달 저장소.
 *
 * <h2>키 설계</h2>
 * <pre>
 *   delivery:{id}          배달 애그리거트 전체 (JSON)      TTL 72h
 *   delivery:status:{id}   추적 API 전용 경량 뷰 (JSON)     TTL 72h   ← 구체화된 뷰
 *   delivery:owner:{owner} 소유 계정별 ID 집합               TTL 72h
 * </pre>
 *
 * <h2>왜 TTL 을 두는가</h2>
 * 완료된 배달은 Delivery History 로 넘어간다. Redis 에 계속 두면 메모리와 비용이 무한히 늘어난다.
 * 핫 저장소는 «지금 필요한 것»만 담는다. 원본은 이벤트 스트림에 있으므로 유실이 아니다.
 */
@Repository
public class RedisDeliveryRepository implements DeliveryRepository {

    private static final Logger log = LoggerFactory.getLogger(RedisDeliveryRepository.class);

    private static final String KEY_AGGREGATE = "delivery:%s";
    private static final String KEY_STATUS    = "delivery:status:%s";
    private static final String KEY_OWNER     = "delivery:owner:%s";
    private static final Duration TTL         = Duration.ofHours(72);

    private final StringRedisTemplate redis;
    private final ObjectMapper mapper;

    public RedisDeliveryRepository(StringRedisTemplate redis, ObjectMapper mapper) {
        this.redis = redis;
        this.mapper = mapper;
    }

    @Override
    public Optional<Delivery> findById(DeliveryId id) {
        String json = redis.opsForValue().get(KEY_AGGREGATE.formatted(id.value()));
        return Optional.ofNullable(json).map(this::deserialize);
    }

    @Override
    public Delivery insert(Delivery delivery) {
        writeAll(delivery);
        return delivery;
    }

    @Override
    public Delivery save(Delivery delivery, long expectedVersion) {
        // 낙관적 동시성 — 저장 직전에 현재 버전을 확인한다.
        // ⚠️ 완전한 원자성이 필요하면 Lua 스크립트로 «검사 후 쓰기»를 한 번에 수행해야 한다.
        //     여기서는 충돌 빈도가 낮은 도메인 특성을 근거로 단순 검사를 쓴다.
        Optional<Delivery> current = findById(delivery.id());
        if (current.isPresent() && current.get().version() != expectedVersion) {
            throw new ConcurrencyConflictException(delivery.id(), expectedVersion);
        }
        writeAll(delivery);
        return delivery;
    }

    @Override
    public void deleteById(DeliveryId id) {
        findById(id).ifPresent(d ->
                redis.opsForSet().remove(KEY_OWNER.formatted(d.ownerId()), id.value()));
        redis.delete(List.of(KEY_AGGREGATE.formatted(id.value()),
                             KEY_STATUS.formatted(id.value())));
    }

    @Override
    public List<Delivery> findByOwner(String ownerId, int limit) {
        Set<String> ids = redis.opsForSet().members(KEY_OWNER.formatted(ownerId));
        if (ids == null || ids.isEmpty()) {
            return List.of();
        }
        List<Delivery> out = new ArrayList<>();
        for (String id : ids) {
            if (out.size() >= limit) {
                break;
            }
            findById(DeliveryId.of(id)).ifPresent(out::add);
        }
        return out;
    }

    private void writeAll(Delivery d) {
        String id = d.id().value();
        redis.opsForValue().set(KEY_AGGREGATE.formatted(id), serialize(d), TTL);
        // ★ 구체화된 뷰 — 추적 API 가 조인 없이 한 번에 읽는다 (NFR-02 p95 150ms)
        redis.opsForValue().set(KEY_STATUS.formatted(id),
                serializeStatus(DeliveryRecord.statusViewOf(d)), TTL);
        redis.opsForSet().add(KEY_OWNER.formatted(d.ownerId()), id);
        redis.expire(KEY_OWNER.formatted(d.ownerId()), TTL);
    }

    private String serialize(Delivery d) {
        try {
            return mapper.writeValueAsString(DeliveryRecord.from(d));
        } catch (Exception e) {
            throw new IllegalStateException("배달 직렬화 실패: " + d.id(), e);
        }
    }

    private String serializeStatus(DeliveryRecord.StatusView v) {
        try {
            return mapper.writeValueAsString(v);
        } catch (Exception e) {
            throw new IllegalStateException("상태 뷰 직렬화 실패", e);
        }
    }

    private Delivery deserialize(String json) {
        try {
            return mapper.readValue(json, DeliveryRecord.class).toDomain();
        } catch (Exception e) {
            log.error("배달 역직렬화 실패 — 스키마 변경 가능성");
            throw new IllegalStateException("배달 역직렬화 실패", e);
        }
    }
}
