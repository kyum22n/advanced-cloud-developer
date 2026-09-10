package com.fabrikam.drone.ingestion.application;

import java.time.Duration;
import java.util.Optional;

/**
 * 멱등 기록 저장소 — 포트.
 *
 * <p>애플리케이션 계층이 Spring Data Redis 에 직접 의존하지 않도록 최소 인터페이스만 둔다.
 * 이 작은 포트 하나로 ① 계층 규칙을 지키고 ② 테스트에서 프레임워크 없이 검증한다.
 */
public interface IdempotencyStore {

    Optional<String> get(String key);

    void put(String key, String value, Duration ttl);
}
