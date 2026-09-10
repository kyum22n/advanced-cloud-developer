package com.fabrikam.drone.delivery.api;

import com.fabrikam.drone.contract.ErrorCodes;
import com.fabrikam.drone.contract.Headers;
import com.fabrikam.drone.delivery.domain.DeliveryRepository;
import com.fabrikam.drone.delivery.domain.InvalidStateTransitionException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.net.URI;
import java.util.NoSuchElementException;

/**
 * 전역 예외 처리 — RFC 9457 Problem Details 로 통일한다.
 *
 * <h2>상태 코드 규약</h2>
 * <ul>
 *   <li>400 — 요청 «형식»이 잘못됨</li>
 *   <li>404 — 리소스 없음</li>
 *   <li>409 — 형식은 맞지만 «현재 상태»에서 불가 (도메인 불변식 위반)</li>
 *   <li>412 — 낙관적 동시성 충돌</li>
 *   <li>500 — 서버 오류. <b>내부 정보를 노출하지 않는다</b></li>
 * </ul>
 * 400 과 409 를 구분하는 이유 — 클라이언트가 «고쳐서 다시 보낼지» 판단하는 근거가 되기 때문이다.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(InvalidStateTransitionException.class)
    public ProblemDetail onInvalidTransition(InvalidStateTransitionException e) {
        ProblemDetail p = base(HttpStatus.CONFLICT, "허용되지 않는 상태 전이", e.getMessage(),
                ErrorCodes.INVALID_STATE_TRANSITION);
        p.setProperty("currentStatus", e.from().name());
        p.setProperty("requestedStatus", e.to().name());
        return p;
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ProblemDetail onNotFound(NoSuchElementException e) {
        return base(HttpStatus.NOT_FOUND, "배달을 찾을 수 없습니다", e.getMessage(),
                ErrorCodes.DELIVERY_NOT_FOUND);
    }

    @ExceptionHandler(DeliveryRepository.ConcurrencyConflictException.class)
    public ProblemDetail onConflict(DeliveryRepository.ConcurrencyConflictException e) {
        return base(HttpStatus.PRECONDITION_FAILED, "동시 변경 충돌", e.getMessage(),
                ErrorCodes.CONCURRENCY_CONFLICT);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ProblemDetail onIllegalArgument(IllegalArgumentException e) {
        return base(HttpStatus.BAD_REQUEST, "요청이 올바르지 않습니다", e.getMessage(),
                ErrorCodes.VALIDATION_FAILED);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail onValidation(MethodArgumentNotValidException e) {
        ProblemDetail p = base(HttpStatus.BAD_REQUEST, "요청이 올바르지 않습니다",
                "입력 값 검증에 실패했습니다.", ErrorCodes.VALIDATION_FAILED);
        p.setProperty("errors", e.getBindingResult().getFieldErrors().stream()
                .map(f -> java.util.Map.of("field", f.getField(),
                        "message", String.valueOf(f.getDefaultMessage())))
                .toList());
        return p;
    }

    @ExceptionHandler(Exception.class)
    public ProblemDetail onUnexpected(Exception e) {
        // ★ 스택 트레이스는 로그에만. 응답에는 내부 구조를 노출하지 않는다 (SEC).
        log.error("처리되지 않은 예외", e);
        return base(HttpStatus.INTERNAL_SERVER_ERROR, "서버 오류",
                "요청을 처리하지 못했습니다. 상관 ID 와 함께 문의해 주세요.",
                ErrorCodes.INTERNAL_ERROR);
    }

    private static ProblemDetail base(HttpStatus status, String title, String detail, String type) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(status, detail);
        p.setTitle(title);
        p.setType(URI.create(type));
        String correlationId = MDC.get(Headers.MDC_CORRELATION_ID);
        if (correlationId != null) {
            p.setProperty("correlationId", correlationId);
        }
        return p;
    }
}
