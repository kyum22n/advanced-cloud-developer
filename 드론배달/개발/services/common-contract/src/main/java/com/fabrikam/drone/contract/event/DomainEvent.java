package com.fabrikam.drone.contract.event;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * 도메인 이벤트 봉투 — 게시된 언어(Published Language).
 *
 * <p>모든 서비스가 이 형식으로 이벤트를 주고받는다. 규약:
 * <ul>
 *   <li>{@code eventId} — 멱등 소비의 열쇠. 소비자는 이 값으로 중복을 걸러낸다.</li>
 *   <li>{@code eventVersion} — 스키마 진화. <b>필드 추가만 허용</b>, 삭제·의미 변경 금지.</li>
 *   <li>{@code correlationId} — 분산 추적. 메시징 구간에서 끊기지 않게 반드시 전파한다.</li>
 *   <li>{@code causationId} — 이 이벤트를 유발한 이벤트. 인과 사슬 추적.</li>
 * </ul>
 *
 * @param eventId       이벤트 고유 ID (멱등 처리용)
 * @param eventType     라우팅 키 (예: DeliveryCompleted)
 * @param eventVersion  스키마 버전 (예: 1.0)
 * @param occurredAt    발생 시각
 * @param aggregateId   발행 애그리거트의 ID
 * @param correlationId 요청 상관 ID
 * @param causationId   원인 이벤트 ID (없으면 null)
 * @param data          이벤트별 페이로드
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record DomainEvent(
        String eventId,
        String eventType,
        String eventVersion,
        Instant occurredAt,
        String aggregateId,
        String correlationId,
        String causationId,
        Map<String, Object> data) {

    public static final String VERSION_1_0 = "1.0";

    public DomainEvent {
        if (eventId == null || eventType == null || aggregateId == null) {
            throw new IllegalArgumentException("eventId · eventType · aggregateId 는 필수입니다.");
        }
        if (eventVersion == null) {
            eventVersion = VERSION_1_0;
        }
        if (occurredAt == null) {
            occurredAt = Instant.now();
        }
        data = data == null ? Map.of() : Map.copyOf(data);
    }

    public static DomainEvent of(String type, String aggregateId,
                                 String correlationId, Map<String, Object> data) {
        return new DomainEvent(UUID.randomUUID().toString(), type, VERSION_1_0,
                Instant.now(), aggregateId, correlationId, null, data);
    }

    /** 이 이벤트를 원인으로 하는 후속 이벤트를 만든다 — 인과 사슬 유지. */
    public DomainEvent caused(String type, String aggregateId, Map<String, Object> data) {
        return new DomainEvent(UUID.randomUUID().toString(), type, VERSION_1_0,
                Instant.now(), aggregateId, this.correlationId, this.eventId, data);
    }
}
