package com.fabrikam.drone.workflow.infrastructure;

import com.fabrikam.drone.workflow.saga.SagaState;
import com.fabrikam.drone.workflow.saga.SagaStateRepository;
import com.fabrikam.drone.workflow.saga.SagaStep;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Repository;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * Saga 진행 상태 저장소 — Redis.
 *
 * <h2>키 설계</h2>
 * <pre>
 *   saga:{deliveryId}   진행 상태 (JSON)            TTL 24h
 *   saga:running        진행 중 Saga 의 정렬 집합    점수 = 시작 시각(epoch ms)
 * </pre>
 *
 * <p>정렬 집합을 쓰는 이유 — Supervisor 가 «시작한 지 오래된 것»을 찾을 때
 * 전체를 훑지 않고 <b>점수 범위 조회</b>로 O(log N) 에 끝낼 수 있다.
 * 키를 전부 스캔하는 {@code KEYS} 명령은 운영 환경에서 Redis 를 멈추게 한다.
 */
@Repository
public class RedisSagaStateRepository implements SagaStateRepository {

    private static final Logger log = LoggerFactory.getLogger(RedisSagaStateRepository.class);

    private static final String KEY_SAGA    = "saga:%s";
    private static final String KEY_RUNNING = "saga:running";
    private static final Duration TTL       = Duration.ofHours(24);

    private final StringRedisTemplate redis;
    private final ObjectMapper mapper;

    public RedisSagaStateRepository(StringRedisTemplate redis, ObjectMapper mapper) {
        this.redis = redis;
        this.mapper = mapper;
    }

    @Override
    public void save(SagaState state) {
        try {
            redis.opsForValue().set(KEY_SAGA.formatted(state.deliveryId()),
                    mapper.writeValueAsString(Snapshot.from(state)), TTL);
        } catch (Exception e) {
            throw new IllegalStateException("Saga 상태 직렬화 실패: " + state.deliveryId(), e);
        }

        if (state.status() == SagaState.SagaStatus.RUNNING) {
            redis.opsForZSet().add(KEY_RUNNING, state.deliveryId(),
                    state.startedAt().toEpochMilli());
        } else {
            // 진행 중이 아니면 감시 대상에서 뺀다 — Supervisor 가 헛일하지 않게.
            redis.opsForZSet().remove(KEY_RUNNING, state.deliveryId());
        }
    }

    @Override
    public Optional<SagaState> findByDeliveryId(String deliveryId) {
        String json = redis.opsForValue().get(KEY_SAGA.formatted(deliveryId));
        if (json == null) {
            return Optional.empty();
        }
        try {
            return Optional.of(mapper.readValue(json, Snapshot.class).toDomain());
        } catch (Exception e) {
            log.error("Saga 상태 역직렬화 실패 — 스키마 변경 가능성");
            return Optional.empty();
        }
    }

    @Override
    public List<SagaState> findStalled(Instant now, Duration timeout, int limit) {
        double cutoff = now.minus(timeout).toEpochMilli();
        Set<String> ids = redis.opsForZSet().rangeByScore(KEY_RUNNING, 0, cutoff, 0, limit);
        if (ids == null || ids.isEmpty()) {
            return List.of();
        }
        List<SagaState> out = new ArrayList<>();
        for (String id : ids) {
            findByDeliveryId(id).ifPresent(out::add);
        }
        return out;
    }

    @Override
    public void delete(String deliveryId) {
        redis.delete(KEY_SAGA.formatted(deliveryId));
        redis.opsForZSet().remove(KEY_RUNNING, deliveryId);
    }

    /** 영속화 표현 — 도메인 객체를 Jackson 어노테이션으로 오염시키지 않는다. */
    record Snapshot(String deliveryId, String correlationId, Instant startedAt,
                    Instant updatedAt, SagaState.SagaStatus status, List<String> completedSteps,
                    String failureReason, int compensationAttempts,
                    String packageId, String droneId) {

        static Snapshot from(SagaState s) {
            return new Snapshot(s.deliveryId(), s.correlationId(), s.startedAt(), s.updatedAt(),
                    s.status(), s.completedSteps().stream().map(Enum::name).toList(),
                    s.failureReason(), s.compensationAttempts(), s.packageId(), s.droneId());
        }

        SagaState toDomain() {
            SagaState s = new SagaState(deliveryId, correlationId, startedAt);
            Set<SagaStep> steps = EnumSet.noneOf(SagaStep.class);
            if (completedSteps != null) {
                completedSteps.forEach(n -> steps.add(SagaStep.valueOf(n)));
            }
            steps.forEach(step -> s.complete(step, updatedAt));
            s.setPackageId(packageId);
            s.setDroneId(droneId);
            switch (status) {
                case SUCCEEDED           -> s.succeed(updatedAt);
                case FAILED              -> s.fail(failureReason, updatedAt);
                case COMPENSATING        -> s.startCompensation(updatedAt);
                case COMPENSATED         -> s.compensated(updatedAt);
                case MANUAL_INTERVENTION -> s.needsManualIntervention(updatedAt);
                case RUNNING             -> { }
            }
            return s;
        }
    }
}
