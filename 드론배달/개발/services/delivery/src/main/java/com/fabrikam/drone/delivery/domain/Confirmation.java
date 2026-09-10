package com.fabrikam.drone.delivery.domain;

import com.fabrikam.drone.contract.vo.Location;

import java.time.Instant;

/**
 * 수령 확인 — Delivery 애그리거트의 하위 엔터티.
 *
 * <p>독립적으로 조회·수정되지 않으며 반드시 Delivery 를 통해서만 접근한다.
 * 그래서 ConfirmationRepository 는 존재하지 않는다.
 */
public record Confirmation(String confirmationId,
                           Instant confirmedAt,
                           Location confirmedLocation,
                           String signatureRef) {

    public Confirmation {
        if (confirmationId == null || confirmedAt == null) {
            throw new IllegalArgumentException("확인 ID 와 확인 시각은 필수입니다.");
        }
    }
}
