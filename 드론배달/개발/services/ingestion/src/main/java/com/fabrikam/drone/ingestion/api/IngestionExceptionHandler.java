package com.fabrikam.drone.ingestion.api;

import com.fabrikam.drone.contract.ErrorCodes;
import com.fabrikam.drone.ingestion.application.IdempotencyGuard;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.net.URI;

/** Ingestion 예외 → RFC 9457 Problem Details. */
@RestControllerAdvice
public class IngestionExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(IngestionExceptionHandler.class);

    @ExceptionHandler(IdempotencyGuard.KeyReusedException.class)
    public ProblemDetail onKeyReused(IdempotencyGuard.KeyReusedException e) {
        // 422 — 형식은 맞지만 처리할 수 없다. 400 이 아니다.
        return problem(HttpStatus.UNPROCESSABLE_ENTITY, "멱등 키 재사용", e.getMessage(),
                ErrorCodes.IDEMPOTENCY_KEY_REUSED);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail onValidation(MethodArgumentNotValidException e) {
        ProblemDetail p = problem(HttpStatus.BAD_REQUEST, "요청이 올바르지 않습니다",
                "입력 값 검증에 실패했습니다.", ErrorCodes.VALIDATION_FAILED);
        p.setProperty("errors", e.getBindingResult().getFieldErrors().stream()
                .map(f -> java.util.Map.of("field", f.getField(),
                        "message", String.valueOf(f.getDefaultMessage()))).toList());
        return p;
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ProblemDetail onIllegalArgument(IllegalArgumentException e) {
        return problem(HttpStatus.BAD_REQUEST, "요청이 올바르지 않습니다", e.getMessage(),
                ErrorCodes.VALIDATION_FAILED);
    }

    @ExceptionHandler(IllegalStateException.class)
    public ProblemDetail onUpstreamFailure(IllegalStateException e) {
        // 큐에 넣지 못한 것은 우리 문제다 — 클라이언트는 잠시 뒤 재시도하면 된다.
        log.error("접수 실패", e);
        ProblemDetail p = problem(HttpStatus.SERVICE_UNAVAILABLE, "일시적으로 접수할 수 없습니다",
                "잠시 후 다시 시도해 주세요.", ErrorCodes.UPSTREAM_UNAVAILABLE);
        p.setProperty("retryAfter", 5);
        return p;
    }

    private static ProblemDetail problem(HttpStatus status, String title,
                                         String detail, String type) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(status, detail);
        p.setTitle(title);
        p.setType(URI.create(type));
        return p;
    }
}
