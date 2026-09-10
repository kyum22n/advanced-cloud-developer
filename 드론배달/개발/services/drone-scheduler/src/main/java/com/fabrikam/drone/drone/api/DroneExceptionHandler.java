package com.fabrikam.drone.drone.api;

import com.fabrikam.drone.contract.ErrorCodes;
import com.fabrikam.drone.drone.domain.DroneRepository;
import com.fabrikam.drone.drone.domain.DroneUnavailableException;
import com.fabrikam.drone.drone.domain.NoAvailableDroneException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.net.URI;
import java.util.NoSuchElementException;

/** 드론 서비스 예외 → RFC 9457 Problem Details. */
@RestControllerAdvice
public class DroneExceptionHandler {

    @ExceptionHandler(NoAvailableDroneException.class)
    public ProblemDetail onNoDrone(NoAvailableDroneException e) {
        // 409 — 요청은 올바르지만 «지금» 처리할 수 없다.
        // Workflow 는 이 코드를 보고 타사 위탁으로 전환한다.
        return problem(HttpStatus.CONFLICT, "가용 드론 없음", e.getMessage(),
                ErrorCodes.NO_AVAILABLE_DRONE);
    }

    @ExceptionHandler(DroneUnavailableException.class)
    public ProblemDetail onUnavailable(DroneUnavailableException e) {
        ProblemDetail p = problem(HttpStatus.CONFLICT, "드론 사용 불가", e.getMessage(),
                ErrorCodes.DRONE_UNAVAILABLE);
        p.setProperty("droneId", e.droneId());
        return p;
    }

    @ExceptionHandler(DroneRepository.OptimisticConcurrencyException.class)
    public ProblemDetail onConflict(DroneRepository.OptimisticConcurrencyException e) {
        return problem(HttpStatus.PRECONDITION_FAILED, "동시 변경 충돌", e.getMessage(),
                ErrorCodes.CONCURRENCY_CONFLICT);
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ProblemDetail onNotFound(NoSuchElementException e) {
        return problem(HttpStatus.NOT_FOUND, "드론을 찾을 수 없습니다", e.getMessage(),
                ErrorCodes.DRONE_NOT_FOUND);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ProblemDetail onIllegalArgument(IllegalArgumentException e) {
        return problem(HttpStatus.BAD_REQUEST, "요청이 올바르지 않습니다", e.getMessage(),
                ErrorCodes.VALIDATION_FAILED);
    }

    private static ProblemDetail problem(HttpStatus status, String title,
                                         String detail, String type) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(status, detail);
        p.setTitle(title);
        p.setType(URI.create(type));
        return p;
    }
}
