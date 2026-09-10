package com.fabrikam.drone.workflow.saga;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

/** Saga 진행 상태 저장소 — 포트. 구현은 Redis. */
public interface SagaStateRepository {

    void save(SagaState state);

    Optional<SagaState> findByDeliveryId(String deliveryId);

    /** 시간 초과된 Saga 를 찾는다 — Supervisor 가 주기적으로 호출한다. */
    List<SagaState> findStalled(Instant now, Duration timeout, int limit);

    void delete(String deliveryId);
}
