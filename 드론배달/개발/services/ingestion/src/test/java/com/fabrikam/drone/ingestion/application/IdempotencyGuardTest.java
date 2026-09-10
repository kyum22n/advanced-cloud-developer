package com.fabrikam.drone.ingestion.application;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 멱등 키 처리 테스트 — 인수 조건 AC-2.
 *
 * <p>포트 하나만 흉내 내면 되므로 Redis 도, 모의 프레임워크도 필요 없다.
 * 이것이 애플리케이션 계층을 인프라에서 떼어 놓는 실용적 이익이다.
 */
@DisplayName("IdempotencyGuard — AC-2 멱등성")
class IdempotencyGuardTest {

    private IdempotencyGuard guard;

    @BeforeEach
    void setUp() {
        guard = new IdempotencyGuard(new InMemoryStore());
    }

    @Test
    @DisplayName("처음 보는 키에는 저장된 응답이 없다")
    void firstRequestHasNoCache() {
        assertTrue(guard.findExisting("key-1", "{\"a\":1}").isEmpty());
    }

    @Test
    @DisplayName("같은 키 · 같은 본문이면 첫 응답을 그대로 돌려준다 — 두 번 처리하지 않는다")
    void sameKeySameBodyReturnsCached() {
        guard.remember("key-1", "{\"a\":1}", "{\"deliveryId\":\"dlv-0001\"}");

        Optional<String> cached = guard.findExisting("key-1", "{\"a\":1}");
        assertTrue(cached.isPresent());
        assertEquals("{\"deliveryId\":\"dlv-0001\"}", cached.get());
    }

    @Test
    @DisplayName("같은 키 · 다른 본문이면 422 로 거부한다 — 키 재사용 오류")
    void sameKeyDifferentBodyRejected() {
        guard.remember("key-1", "{\"a\":1}", "{\"deliveryId\":\"dlv-0001\"}");

        assertThrows(IdempotencyGuard.KeyReusedException.class,
                () -> guard.findExisting("key-1", "{\"a\":2}"));
    }

    @Test
    @DisplayName("공백 하나만 달라도 다른 본문으로 본다 — 해시 기반이므로")
    void whitespaceMatters() {
        guard.remember("key-1", "{\"a\":1}", "resp");
        assertThrows(IdempotencyGuard.KeyReusedException.class,
                () -> guard.findExisting("key-1", "{\"a\": 1}"));
    }

    @Test
    @DisplayName("다른 키는 서로 간섭하지 않는다")
    void differentKeysAreIndependent() {
        guard.remember("key-1", "{\"a\":1}", "resp-1");
        guard.remember("key-2", "{\"a\":1}", "resp-2");

        assertEquals("resp-1", guard.findExisting("key-1", "{\"a\":1}").orElseThrow());
        assertEquals("resp-2", guard.findExisting("key-2", "{\"a\":1}").orElseThrow());
    }

    @Test
    @DisplayName("본문이 null 이어도 동작한다")
    void handlesNullBody() {
        guard.remember("key-1", null, "resp");
        assertEquals("resp", guard.findExisting("key-1", null).orElseThrow());
    }

    @Test
    @DisplayName("응답 안에 구분자와 비슷한 문자가 있어도 잘리지 않는다")
    void responseWithSpecialCharacters() {
        String response = "{\"note\":\"a\\u001fb\"}";
        guard.remember("key-1", "{}", response);
        assertEquals(response, guard.findExisting("key-1", "{}").orElseThrow());
    }

    /** 메모리 기반 저장소 — TTL 은 이 테스트에서 검증 대상이 아니다. */
    static class InMemoryStore implements IdempotencyStore {

        private final Map<String, String> store = new HashMap<>();

        @Override
        public Optional<String> get(String key) {
            return Optional.ofNullable(store.get(key));
        }

        @Override
        public void put(String key, String value, Duration ttl) {
            store.put(key, value);
        }
    }
}
