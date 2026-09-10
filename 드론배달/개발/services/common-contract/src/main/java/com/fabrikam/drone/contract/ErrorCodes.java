package com.fabrikam.drone.contract;

/**
 * 오류 유형 URI — RFC 9457 Problem Details 의 {@code type} 필드.
 *
 * <p>클라이언트는 사람이 읽는 {@code title} 이 아니라 이 URI 로 분기해야 한다.
 * 그래야 문구가 바뀌어도 클라이언트가 깨지지 않는다.
 */
public final class ErrorCodes {

    private ErrorCodes() {
    }

    private static final String BASE = "https://fabrikam.example/errors/";

    public static final String VALIDATION_FAILED         = BASE + "validation-failed";
    public static final String INVALID_STATE_TRANSITION  = BASE + "invalid-state-transition";
    public static final String DELIVERY_NOT_FOUND        = BASE + "delivery-not-found";
    public static final String PACKAGE_NOT_FOUND         = BASE + "package-not-found";
    public static final String DRONE_NOT_FOUND           = BASE + "drone-not-found";
    public static final String NO_AVAILABLE_DRONE        = BASE + "no-available-drone";
    public static final String DRONE_UNAVAILABLE         = BASE + "drone-unavailable";
    public static final String ACCOUNT_INACTIVE          = BASE + "account-inactive";
    public static final String IDEMPOTENCY_KEY_REUSED    = BASE + "idempotency-key-reused";
    public static final String IDEMPOTENCY_KEY_MISSING   = BASE + "idempotency-key-missing";
    public static final String CONCURRENCY_CONFLICT      = BASE + "concurrency-conflict";
    public static final String UPSTREAM_UNAVAILABLE      = BASE + "upstream-unavailable";
    public static final String INTERNAL_ERROR            = BASE + "internal-error";
}
