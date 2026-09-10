package com.fabrikam.drone.contract.vo;

import java.time.Duration;
import java.time.Instant;

/**
 * 예상 도착 시간 — 값 개체.
 *
 * <p>ETA 는 갱신되는 것이 아니라 «교체»된다. 새 위치가 들어오면 새 Eta 를 만든다.
 * 이것이 값 개체를 불변으로 두는 실용적 이유다 — 부분 갱신으로 인한 모순이 없다.
 *
 * @param arrivalTime 예상 도착 시각
 * @param estimatedAt 이 예측을 산출한 시각
 * @param confidence  신뢰도 0.0 ~ 1.0
 */
public record Eta(Instant arrivalTime, Instant estimatedAt, double confidence) {

    public Eta {
        if (arrivalTime == null || estimatedAt == null) {
            throw new IllegalArgumentException("도착 시각과 산출 시각은 필수입니다.");
        }
        if (confidence < 0.0 || confidence > 1.0) {
            throw new IllegalArgumentException("신뢰도는 0.0 ~ 1.0 이어야 합니다: " + confidence);
        }
    }

    /** INV-06 — ETA 는 산출 시점 기준으로 미래여야 한다. */
    public boolean isFuture() {
        return arrivalTime.isAfter(estimatedAt);
    }

    public Duration remaining(Instant now) {
        Duration d = Duration.between(now, arrivalTime);
        return d.isNegative() ? Duration.ZERO : d;
    }
}
