package com.fabrikam.drone.contract.vo;

import java.time.Instant;

/**
 * 시간 구간 — 값 개체. 픽업 희망 시간대를 표현한다.
 */
public record TimeWindow(Instant earliest, Instant latest) {

    public TimeWindow {
        if (earliest == null || latest == null) {
            throw new IllegalArgumentException("시작·종료 시각은 필수입니다.");
        }
        if (!earliest.isBefore(latest)) {
            throw new IllegalArgumentException("시작 시각은 종료 시각보다 이전이어야 합니다.");
        }
    }

    public boolean contains(Instant t) {
        return !t.isBefore(earliest) && !t.isAfter(latest);
    }
}
