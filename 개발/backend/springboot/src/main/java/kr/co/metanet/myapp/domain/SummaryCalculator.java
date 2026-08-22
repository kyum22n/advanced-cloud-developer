package kr.co.metanet.myapp.domain;

import java.math.BigDecimal;
import java.time.ZoneOffset;
import java.time.temporal.WeekFields;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * 주차 집계 — 외부 의존이 없는 순수 로직이므로 단위 테스트로 고정한다.
 *
 * <p>설계 근거: 설계/공통/02_도메인·클래스설계서.md, 설계/공통/06_테스트설계서.md (U-A-01~05)</p>
 */
public final class SummaryCalculator {

    private static final WeekFields ISO = WeekFields.ISO;

    private SummaryCalculator() {
    }

    /**
     * ISO 8601 주차 문자열을 만든다.
     *
     * @param item 대상 항목
     * @return 예 {@code 2026-W10}
     */
    public static String isoWeek(Item item) {
        var date = item.createdAt().atZone(ZoneOffset.UTC).toLocalDate();
        int week = date.get(ISO.weekOfWeekBasedYear());
        int year = date.get(ISO.weekBasedYear());
        return String.format(Locale.ROOT, "%d-W%02d", year, week);
    }

    /**
     * 주차별로 건수와 금액을 집계한다. 빈 입력은 예외가 아니라 빈 결과다.
     *
     * @param items 항목 목록
     * @return 주차 오름차순 집계
     */
    public static List<WeekSummary> summarizeByWeek(List<Item> items) {
        if (items == null) {
            throw new IllegalArgumentException("items 는 null 일 수 없습니다.");
        }
        Map<String, int[]> counts = new LinkedHashMap<>();
        Map<String, BigDecimal> amounts = new LinkedHashMap<>();
        for (Item item : items) {
            String week = isoWeek(item);
            counts.computeIfAbsent(week, k -> new int[1])[0]++;
            amounts.merge(week, nullSafe(item.amount()), BigDecimal::add);
        }
        List<WeekSummary> result = new ArrayList<>();
        counts.keySet().stream().sorted().forEach(week ->
                result.add(new WeekSummary(week, counts.get(week)[0], amounts.get(week))));
        return result;
    }

    /**
     * 같은 식별자가 여러 번 나오면 마지막 값만 남긴다.
     *
     * @param items 항목 목록
     * @return 중복이 제거된 목록
     */
    public static List<Item> dedupeById(List<Item> items) {
        Map<Long, Item> byId = new LinkedHashMap<>();
        for (Item item : items) {
            byId.put(item.id(), item);
        }
        return new ArrayList<>(byId.values());
    }

    private static BigDecimal nullSafe(BigDecimal value) {
        return value == null ? BigDecimal.ZERO : value;
    }
}
