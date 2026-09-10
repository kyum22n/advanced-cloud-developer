package com.fabrikam.drone.contract;

/** 서비스 간 규약 헤더 — 오타 방지를 위해 상수로만 사용한다. */
public final class Headers {

    private Headers() {
    }

    /** 분산 추적 상관 ID. 없으면 게이트웨이 또는 첫 서비스가 생성한다. */
    public static final String CORRELATION_ID = "X-Correlation-Id";

    /** 멱등 키. 공개 POST 엔드포인트에서 필수. */
    public static final String IDEMPOTENCY_KEY = "Idempotency-Key";

    /** MDC 키 — 구조화 로그 필드명과 일치시킨다. */
    public static final String MDC_CORRELATION_ID = "correlationId";
    public static final String MDC_DELIVERY_ID    = "deliveryId";
}
