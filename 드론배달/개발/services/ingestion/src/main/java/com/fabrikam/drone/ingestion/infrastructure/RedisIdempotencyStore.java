package com.fabrikam.drone.ingestion.infrastructure;

import com.fabrikam.drone.ingestion.application.IdempotencyStore;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Optional;

/** 멱등 기록 저장소 구현 — Redis. TTL 24시간은 최대 재전달 창보다 충분히 길다. */
@Component
public class RedisIdempotencyStore implements IdempotencyStore {

    private final StringRedisTemplate redis;

    public RedisIdempotencyStore(StringRedisTemplate redis) {
        this.redis = redis;
    }

    @Override
    public Optional<String> get(String key) {
        return Optional.ofNullable(redis.opsForValue().get(key));
    }

    @Override
    public void put(String key, String value, Duration ttl) {
        redis.opsForValue().set(key, value, ttl);
    }
}
