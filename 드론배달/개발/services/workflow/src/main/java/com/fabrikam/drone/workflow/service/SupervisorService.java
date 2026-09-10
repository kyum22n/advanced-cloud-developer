package com.fabrikam.drone.workflow.service;

import com.fabrikam.drone.workflow.saga.SagaState;
import com.fabrikam.drone.workflow.saga.SagaStateRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.util.List;

/**
 * 감독자 — 스케줄러 에이전트 감독자 패턴의 «감독자».
 *
 * <h2>왜 Scheduler 와 분리되어야 하는가</h2>
 * Scheduler 가 ③단계까지 수행하고 <b>인스턴스가 죽으면</b>, 아무도 보상을 실행하지 않는다.
 * 큐 메시지의 락이 풀려 다른 인스턴스가 재처리하지만, 계속 죽는 상황이면 무한 반복된다.
 *
 * <p>Supervisor 는 Scheduler 와 <b>독립적으로</b> 진행 상태를 훑으며
 * «시작한 지 오래됐는데 끝나지 않은» Saga 를 찾아 보상한다.
 *
 * <h2>왜 별도 서비스로 배포하지 않는가 (ADR-002)</h2>
 * 부하가 고정적이고 매우 낮아, 서비스 하나를 늘리는 운영 비용이 이익보다 크다.
 * 대신 <b>의존성을 단방향으로</b> 유지해 언제든 분리할 수 있게 둔다 —
 * Supervisor 는 Scheduler 를 알지만, Scheduler 는 Supervisor 를 모른다.
 *
 * <p>여러 인스턴스가 동시에 같은 Saga 를 보상해도 안전하다 —
 * 모든 보상 연산이 멱등하기 때문이다. 그래서 리더 선출이 필요 없다.
 */
@Service
public class SupervisorService {

    private static final Logger log = LoggerFactory.getLogger(SupervisorService.class);

    /** 한 번에 처리할 최대 건수 — 한 번의 스캔이 너무 오래 걸리지 않게 한다. */
    private static final int SCAN_LIMIT = 50;

    private final SagaStateRepository sagaStates;
    private final SchedulerService scheduler;
    private final WorkflowMetrics metrics;
    private final Clock clock;
    private final Duration timeout;

    public SupervisorService(SagaStateRepository sagaStates,
                             SchedulerService scheduler,
                             WorkflowMetrics metrics,
                             Clock clock,
                             @Value("${drone.saga.timeout-seconds:300}") long timeoutSeconds) {
        this.sagaStates = sagaStates;
        this.scheduler = scheduler;
        this.metrics = metrics;
        this.clock = clock;
        this.timeout = Duration.ofSeconds(timeoutSeconds);
    }

    /**
     * 시간 초과된 Saga 를 찾아 보상한다 — POL-07.
     *
     * <p>{@code fixedDelay} 를 쓴다 — 이전 실행이 끝난 뒤 30초를 센다.
     * {@code fixedRate} 였다면 스캔이 30초를 넘길 때 실행이 겹친다.
     */
    @Scheduled(fixedDelayString = "${drone.supervisor.scan-interval-ms:30000}")
    public void scanForStalledSagas() {
        var now = clock.instant();
        List<SagaState> stalled = sagaStates.findStalled(now, timeout, SCAN_LIMIT);
        if (stalled.isEmpty()) {
            return;
        }

        log.warn("시간 초과된 Saga {}건을 발견했습니다 (임계값 {}초)", stalled.size(), timeout.toSeconds());
        metrics.stalledDetected(stalled.size());

        for (SagaState saga : stalled) {
            try {
                saga.fail("처리 시간 초과 — timeout %d초".formatted(timeout.toSeconds()), now);
                scheduler.compensate(saga);
            } catch (RuntimeException e) {
                // 한 건의 실패가 나머지 스캔을 막지 않게 한다.
                log.error("Saga 보상 중 오류 — 다음 건으로 진행합니다: {}", e.getMessage());
            }
        }
    }

    /** 수동 개입이 필요한 Saga 목록 — 운영 대시보드용. */
    public List<SagaState> findRequiringIntervention() {
        return sagaStates.findStalled(clock.instant(), Duration.ZERO, SCAN_LIMIT).stream()
                .filter(s -> s.status() == SagaState.SagaStatus.MANUAL_INTERVENTION)
                .toList();
    }
}
