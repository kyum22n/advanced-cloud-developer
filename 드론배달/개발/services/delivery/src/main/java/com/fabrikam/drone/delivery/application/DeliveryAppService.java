package com.fabrikam.drone.delivery.application;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.contract.vo.Eta;
import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.contract.vo.TimeWindow;
import com.fabrikam.drone.delivery.domain.Confirmation;
import com.fabrikam.drone.delivery.domain.Delivery;
import com.fabrikam.drone.delivery.domain.DeliveryId;
import com.fabrikam.drone.delivery.domain.DeliveryRepository;
import com.fabrikam.drone.delivery.domain.EtaCalculator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.UUID;

/**
 * 배달 애플리케이션 서비스 — 유스케이스 조정.
 *
 * <p>이 계층이 <b>하는 일</b>: 애그리거트 로드 → 도메인 메서드 호출 → 저장 → 이벤트 발행.
 * <p>이 계층이 <b>하지 않는 일</b>: 비즈니스 규칙 판단. 그것은 애그리거트의 몫이다.
 *
 * <p>판별법 — 이 클래스에 상태 전이 조건을 검사하는 {@code if} 가 있다면 설계가 새고 있는 것이다.
 */
@Service
public class DeliveryAppService {

    private static final Logger log = LoggerFactory.getLogger(DeliveryAppService.class);

    private final DeliveryRepository repository;
    private final DeliveryEventPublisher publisher;
    private final EtaCalculator etaCalculator;
    private final DeliveryMetrics metrics;
    private final Clock clock;

    public DeliveryAppService(DeliveryRepository repository,
                              DeliveryEventPublisher publisher,
                              EtaCalculator etaCalculator,
                              DeliveryMetrics metrics,
                              Clock clock) {
        this.repository = repository;
        this.publisher = publisher;
        this.etaCalculator = etaCalculator;
        this.metrics = metrics;
        this.clock = clock;
    }

    /**
     * 배달을 생성하거나(신규) 이미 있으면 그대로 반환한다(멱등).
     *
     * <p>PUT 의미론 — Workflow 가 재시도해도 배달이 두 번 만들어지지 않는다.
     */
    public Delivery upsert(DeliveryId id, String ownerId, String packageId,
                           Location pickup, Location dropoff, TimeWindow window,
                           String correlationId) {
        var existing = repository.findById(id);
        if (existing.isPresent()) {
            log.info("이미 존재하는 배달입니다 — 멱등 반환");
            return existing.get();
        }

        Instant now = clock.instant();
        Delivery delivery = Delivery.create(id, ownerId, packageId, pickup, dropoff,
                window, correlationId, now);
        Delivery saved = repository.insert(delivery);
        publish(saved);
        metrics.created();
        log.info("배달 생성 완료");
        return saved;
    }

    public Delivery assignDrone(DeliveryId id, String droneId, String correlationId) {
        Delivery d = load(id);
        long expected = d.version();
        d.assignDrone(droneId, correlationId, clock.instant());
        Delivery saved = repository.save(d, expected);
        publish(saved);
        return saved;
    }

    public Delivery cancel(DeliveryId id, String reason, String correlationId) {
        Delivery d = load(id);
        long expected = d.version();
        d.cancel(reason, correlationId, clock.instant());          // ← INV-01 은 여기서 검사된다
        Delivery saved = repository.save(d, expected);
        publish(saved);
        metrics.cancelled();
        return saved;
    }

    public Delivery complete(DeliveryId id, String signatureRef, Location at, String correlationId) {
        Delivery d = load(id);
        long expected = d.version();
        Instant now = clock.instant();
        d.complete(new Confirmation(UUID.randomUUID().toString(), now, at, signatureRef),
                correlationId, now);
        Delivery saved = repository.save(d, expected);
        publish(saved);
        metrics.completed(d.createdAt(), now);
        return saved;
    }

    public Delivery fail(DeliveryId id, String reason, String correlationId) {
        Delivery d = load(id);
        long expected = d.version();
        d.fail(reason, correlationId, clock.instant());
        Delivery saved = repository.save(d, expected);
        publish(saved);
        metrics.failed(reason);
        return saved;
    }

    /**
     * 드론 위치 변경을 반영하고 ETA 를 재계산한다 — POL-04.
     *
     * <p>DroneStatus 이벤트 구독으로 호출된다.
     */
    public void applyDroneLocation(DeliveryId id, Location location,
                                   Instant reportedAt, String correlationId) {
        var found = repository.findById(id);
        if (found.isEmpty()) {
            log.debug("알 수 없는 배달의 위치 이벤트 — 무시");
            return;
        }
        Delivery d = found.get();
        long expected = d.version();
        Instant now = clock.instant();

        d.updateLocation(location, now);
        if (!d.status().isTerminal()) {
            double confidence = etaCalculator.confidenceFor(reportedAt, now);
            Eta eta = etaCalculator.estimate(location, d.dropoff(), now, confidence);
            d.updateEta(eta, now);
        }
        repository.save(d, expected);
    }

    public Delivery get(DeliveryId id) {
        return load(id);
    }

    public List<Delivery> findByOwner(String ownerId, int limit) {
        return repository.findByOwner(ownerId, limit);
    }

    public void delete(DeliveryId id) {
        repository.deleteById(id);            // 보상 트랜잭션 — 없어도 성공으로 본다
    }

    private Delivery load(DeliveryId id) {
        return repository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("배달을 찾을 수 없습니다: " + id));
    }

    private void publish(Delivery d) {
        for (DomainEvent e : d.drainEvents()) {
            publisher.publish(e);
        }
    }
}
