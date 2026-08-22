package kr.co.metanet.myapp.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** 단위 테스트 — 설계/공통/06 의 U-A-01~05 에 대응한다. */
class SummaryCalculatorTest {

    private static Item item(long id, String iso, String amount) {
        return new Item(id, "t" + id, new BigDecimal(amount), Instant.parse(iso));
    }

    @Test
    @DisplayName("U-A-01 같은 주의 월요일과 일요일은 동일한 주차")
    void sameWeek() {
        String monday = SummaryCalculator.isoWeek(item(1, "2026-03-02T00:00:00Z", "0"));
        String sunday = SummaryCalculator.isoWeek(item(2, "2026-03-08T23:59:59Z", "0"));
        assertEquals(monday, sunday);
    }

    @Test
    @DisplayName("U-A-02 주차별 건수와 합계를 집계")
    void summarize() {
        List<WeekSummary> weeks = SummaryCalculator.summarizeByWeek(List.of(
                item(1, "2026-03-02T00:00:00Z", "100"),
                item(2, "2026-03-03T00:00:00Z", "200"),
                item(3, "2026-03-10T00:00:00Z", "50")));
        assertEquals(2, weeks.size());
        assertEquals(2, weeks.get(0).count());
        assertEquals(0, new BigDecimal("300").compareTo(weeks.get(0).amount()));
    }

    @Test
    @DisplayName("U-A-03 빈 입력은 예외가 아니라 빈 결과")
    void empty() {
        assertTrue(SummaryCalculator.summarizeByWeek(List.of()).isEmpty());
    }

    @Test
    @DisplayName("U-A-04 null 입력은 예외")
    void nullInput() {
        assertThrows(IllegalArgumentException.class, () -> SummaryCalculator.summarizeByWeek(null));
    }

    @Test
    @DisplayName("U-A-05 같은 id 는 마지막 값만 남는다")
    void dedupe() {
        List<Item> deduped = SummaryCalculator.dedupeById(List.of(
                item(1, "2026-03-02T00:00:00Z", "10"),
                item(1, "2026-03-02T00:00:00Z", "20"),
                item(2, "2026-03-02T00:00:00Z", "30")));
        assertEquals(2, deduped.size());
        assertEquals(0, new BigDecimal("20").compareTo(deduped.get(0).amount()));
    }
}
