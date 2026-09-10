package com.fabrikam.drone.delivery.application;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

/**
 * 도메인 메트릭.
 *
 * <p>기술 메트릭(CPU·응답 시간)만으로는 «사업이 잘 돌아가는지» 알 수 없다.
 * 실패 «원인»별 분포가 있어야 «드론이 부족한 것»과 «코드가 깨진 것»을 구분할 수 있다.
 *
 * <p>⚠️ deliveryId 를 태그로 넣지 않는다 — 시계열이 무한히 늘어 비용이 폭발한다.
 * 높은 카디널리티 값은 메트릭이 아니라 로그·추적에 넣는다.
 */
@Component
public class DeliveryMetrics {

    private final MeterRegistry registry;
    private final Counter created;
    private final Counter completed;
    private final Counter cancelled;
    private final Timer duration;

    public DeliveryMetrics(MeterRegistry registry) {
        this.registry = registry;
        this.created = Counter.builder("drone.delivery.created")
                .description("생성에 성공한 배달 수").register(registry);
        this.completed = Counter.builder("drone.delivery.completed")
                .description("완료된 배달 수").register(registry);
        this.cancelled = Counter.builder("drone.delivery.cancelled")
                .description("취소된 배달 수").register(registry);
        this.duration = Timer.builder("drone.delivery.duration")
                .description("예약 접수부터 완료까지 소요 시간")
                .publishPercentiles(0.5, 0.95, 0.99)
                .register(registry);
    }

    public void created()   { created.increment(); }
    public void cancelled() { cancelled.increment(); }

    public void completed(Instant createdAt, Instant completedAt) {
        completed.increment();
        duration.record(Duration.between(createdAt, completedAt));
    }

    /** 실패는 «원인»별로 센다 — 원인 없는 실패 카운터는 조사에 쓸모가 없다. */
    public void failed(String reason) {
        Counter.builder("drone.delivery.failed")
                .description("실패한 배달 수")
                .tag("reason", normalize(reason))
                .register(registry)
                .increment();
    }

    /** 카디널리티 방어 — 자유 문자열을 그대로 태그로 쓰면 시계열이 폭발한다. */
    private static String normalize(String reason) {
        if (reason == null || reason.isBlank()) {
            return "unknown";
        }
        String r = reason.toLowerCase();
        if (r.contains("drone"))    return "no_drone";
        if (r.contains("package"))  return "package_error";
        if (r.contains("account"))  return "account_inactive";
        if (r.contains("timeout"))  return "timeout";
        if (r.contains("third"))    return "thirdparty_error";
        return "other";
    }
}
