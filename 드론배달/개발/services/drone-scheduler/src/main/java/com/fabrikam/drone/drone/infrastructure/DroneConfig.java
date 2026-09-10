package com.fabrikam.drone.drone.infrastructure;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.drone.domain.DroneAssignmentService;
import com.fabrikam.drone.drone.domain.DroneRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.util.function.Consumer;

/** 드론 서비스 구성. */
@Configuration
public class DroneConfig {

    private static final Logger log = LoggerFactory.getLogger(DroneConfig.class);

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }

    @Bean
    public DroneAssignmentService droneAssignmentService(DroneRepository repository) {
        return new DroneAssignmentService(repository);
    }

    /**
     * 이벤트 발행기 — 실제 배포 시 Event Hubs 클라이언트로 교체한다.
     * 본 산출물은 «실행하지 않음»이 전제이므로 로그 발행기를 기본값으로 둔다.
     */
    @Bean
    public Consumer<DomainEvent> droneEventPublisher() {
        return e -> log.info("[이벤트 발행] type={} aggregate={}", e.eventType(), e.aggregateId());
    }
}
