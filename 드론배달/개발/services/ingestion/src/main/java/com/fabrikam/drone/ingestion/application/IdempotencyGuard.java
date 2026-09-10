package com.fabrikam.drone.ingestion.application;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.HexFormat;
import java.util.Optional;

/**
 * 멱등 키 처리 — 인수 조건 AC-2.
 *
 * <h2>왜 POST 에 멱등 키가 필요한가</h2>
 * 클라이언트가 배달 ID 를 모르므로 {@code POST} 를 쓸 수밖에 없다.
 * 그런데 네트워크 오류로 응답을 못 받은 클라이언트는 재시도한다.
 * 멱등 키가 없으면 <b>같은 배달이 두 번 접수</b>된다.
 *
 * <h2>본문 해시를 함께 저장하는 이유</h2>
 * 같은 키로 <b>다른 내용</b>을 보내는 것은 «재시도»가 아니라 «키 재사용 오류»다.
 * 이때 첫 응답을 그대로 돌려주면 클라이언트는 자기가 보낸 내용이 저장된 줄 안다.
 * 422 로 명확히 거부해야 한다.
 */
@Component
public class IdempotencyGuard {

    private static final Logger log = LoggerFactory.getLogger(IdempotencyGuard.class);

    private static final String KEY = "idem:%s";
    private static final Duration TTL = Duration.ofHours(24);
    /** 단위 구분자 — JSON 본문에 나타나지 않는 제어 문자. */
    private static final String SEPARATOR = "\u001f";

    private final IdempotencyStore store;

    public IdempotencyGuard(IdempotencyStore store) {
        this.store = store;
    }

    /**
     * 이 키로 이미 처리한 결과가 있으면 돌려준다.
     *
     * @throws KeyReusedException 같은 키로 다른 본문을 보냈을 때
     */
    public Optional<String> findExisting(String idempotencyKey, String requestBody) {
        Optional<String> stored = store.get(KEY.formatted(idempotencyKey));
        if (stored.isEmpty()) {
            return Optional.empty();
        }
        String raw = stored.get();
        int sep = raw.indexOf(SEPARATOR);
        String storedHash = sep < 0 ? "" : raw.substring(0, sep);
        String storedResponse = sep < 0 ? raw : raw.substring(sep + 1);

        if (!storedHash.equals(hash(requestBody))) {
            log.warn("멱등 키 재사용 — 본문이 다릅니다");
            throw new KeyReusedException(idempotencyKey);
        }
        return Optional.of(storedResponse);
    }

    /** 처리 결과를 기록한다. 재시도가 오면 이 응답을 그대로 돌려준다. */
    public void remember(String idempotencyKey, String requestBody, String response) {
        store.put(KEY.formatted(idempotencyKey),
                hash(requestBody) + SEPARATOR + response, TTL);
    }

    private static String hash(String body) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(
                    md.digest(body == null ? new byte[0] : body.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException("해시 계산 실패", e);
        }
    }

    /** 같은 멱등 키로 다른 본문 — HTTP 422. */
    public static class KeyReusedException extends RuntimeException {
        public KeyReusedException(String key) {
            super("동일한 Idempotency-Key 로 다른 내용을 보냈습니다.");
        }
    }
}
