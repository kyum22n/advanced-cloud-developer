package kr.co.metanet.myapp.domain;

import java.math.BigDecimal;

/**
 * ISO 주차 집계 결과.
 *
 * @param week   ISO 주차 (예: 2026-W10)
 * @param count  건수
 * @param amount 금액 합계
 */
public record WeekSummary(String week, int count, BigDecimal amount) {
}
