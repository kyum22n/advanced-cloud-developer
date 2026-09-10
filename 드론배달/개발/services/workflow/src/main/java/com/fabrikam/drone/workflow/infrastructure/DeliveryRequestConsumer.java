package com.fabrikam.drone.workflow.infrastructure;

import com.fabrikam.drone.workflow.message.DeliveryRequestMessage;
import com.fabrikam.drone.workflow.service.SchedulerService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.Map;

/**
 * 배달 요청 큐 소비자 — 경쟁 소비자 패턴.
 *
 * <p>여러 Workflow 인스턴스가 같은 큐를 소비한다. Service Bus 의 피어‑락이
 * «하나의 메시지를 한 인스턴스만 처리»하도록 보장한다.
 *
 * <h2>멱등 소비가 필수인 이유</h2>
 * 큐는 «최소 1회» 전달이다. 락 만료·인스턴스 재시작·네트워크 오류로 <b>중복은 반드시 온다</b>.
 * 멱등 처리가 없으면 배달이 두 번 생성되고 드론이 두 대 할당된다.
 *
 * <p>실제 리스너 어노테이션({@code @ServiceBusListener} 등)은 배포 환경에서 연결한다.
 * 이 클래스는 «메시지를 받은 뒤의 처리»를 담당하며, 그래서 테스트가 쉽다.
 */
@Component
public class DeliveryRequestConsumer {

    private static final Logger log = LoggerFactory.getLogger(DeliveryRequestConsumer.class);

    private static final String KEY_PROCESSED = "event:processed:%s";
    private static final Duration DEDUP_TTL = Duration.ofHours(24);

    private final SchedulerService scheduler;
    private final ObjectMapper mapper;
    private final StringRedisTemplate redis;

    public DeliveryRequestConsumer(SchedulerService scheduler, ObjectMapper mapper,
                                   StringRedisTemplate redis) {
        this.scheduler = scheduler;
        this.mapper = mapper;
        this.redis = redis;
    }

    /**
     * 메시지를 처리한다.
     *
     * @param messageId       메시지 고유 ID (Service Bus MessageId) — 중복 제거의 열쇠
     * @param body            JSON 본문
     * @param applicationProps 메시지 속성 — 여기에 correlationId 가 들어 있다
     */
    public void handle(String messageId, String body, Map<String, Object> applicationProps) {
        // ★ 메시징 구간의 상관 ID 전파 — 이것이 빠지면 분산 추적이 큐에서 끊긴다.
        String correlationId = applicationProps == null ? null
                : String.valueOf(applicationProps.getOrDefault("correlationId", ""));
        MDC.put("correlationId", correlationId);

        try {
            if (!markIfAbsent(messageId)) {
                log.debug("중복 메시지 — 무시합니다");
                return;
            }
            DeliveryRequestMessage request = mapper.readValue(body, DeliveryRequestMessage.class);
            scheduler.execute(request);

        } catch (com.fasterxml.jackson.core.JacksonException e) {
            // 형식이 깨진 메시지는 재시도해도 소용없다 — 즉시 DLQ 로 보낸다.
            log.error("메시지 형식 오류 — 재시도하지 않고 배달 못한 편지 큐로 보냅니다");
            throw new PoisonMessageException("메시지 역직렬화 실패", e);
        } catch (RuntimeException e) {
            // 그 외 실패는 락 해제 → 재전달 → 최대 5회 후 DLQ.
            log.error("메시지 처리 실패 — 재전달됩니다: {}", e.getMessage());
            throw e;
        } finally {
            MDC.clear();
        }
    }

    /**
     * 멱등 표시 — 처음 보는 메시지면 true.
     *
     * <p>{@code SET key value NX EX ttl} 은 원자적이다. 여러 인스턴스가 동시에
     * 같은 메시지를 처리하려 해도 하나만 true 를 받는다.
     */
    private boolean markIfAbsent(String messageId) {
        Boolean first = redis.opsForValue()
                .setIfAbsent(KEY_PROCESSED.formatted(messageId), "1", DEDUP_TTL);
        return Boolean.TRUE.equals(first);
    }

    /** 재시도해도 소용없는 메시지 — 즉시 DLQ 대상. */
    public static class PoisonMessageException extends RuntimeException {
        public PoisonMessageException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
