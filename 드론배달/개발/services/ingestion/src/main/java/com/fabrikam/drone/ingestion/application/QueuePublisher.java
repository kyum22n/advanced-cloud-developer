package com.fabrikam.drone.ingestion.application;

/**
 * 큐 게시 포트.
 *
 * @implNote {@code messageId} 를 배달 ID 로 두면 Service Bus 의 중복 감지가
 *           «같은 배달의 중복 메시지»를 자동으로 걸러낸다.
 */
public interface QueuePublisher {

    /**
     * @param messageId     중복 감지 키 (= deliveryId)
     * @param body          JSON 본문
     * @param correlationId ★ 메시지 속성으로 전파 — 없으면 분산 추적이 큐에서 끊긴다
     */
    void publish(String messageId, String body, String correlationId);
}
