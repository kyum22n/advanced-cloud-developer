package com.fabrikam.drone.drone.domain;

import java.math.BigDecimal;

/** 조건에 맞는 가용 드론이 없다. HTTP 409 → Workflow 가 타사 위탁으로 전환한다. */
public class NoAvailableDroneException extends RuntimeException {

    public NoAvailableDroneException(BigDecimal requiredKg) {
        super("요청 용량 %s kg 을 처리할 수 있는 가용 드론이 없습니다.".formatted(requiredKg));
    }
}
