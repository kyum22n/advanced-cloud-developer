package com.fabrikam.drone.workflow.agent;

/**
 * 계정 서비스 에이전트 — 포트.
 *
 * <p>Scheduler 가 직접 HTTP 를 호출하면 재시도·회로 차단기 로직이 Scheduler 에 섞인다.
 * 에이전트로 감싸면 Scheduler 는 «순서»에만 집중하고,
 * 각 에이전트가 «그 서비스 고유의 실패 특성»을 갖는다.
 */
public interface AccountAgent {

    /** 계정이 배달을 요청할 수 있는 상태인지 확인한다. */
    boolean isActive(String accountId, String correlationId);
}
