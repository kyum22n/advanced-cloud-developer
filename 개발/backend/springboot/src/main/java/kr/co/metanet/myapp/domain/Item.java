package kr.co.metanet.myapp.domain;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * 항목 도메인 값. 불변으로 두어 계층을 넘나들 때 상태가 변하지 않게 한다.
 *
 * @param id        식별자
 * @param title     제목
 * @param amount    금액
 * @param createdAt 생성 시각
 */
public record Item(long id, String title, BigDecimal amount, Instant createdAt) {
}
