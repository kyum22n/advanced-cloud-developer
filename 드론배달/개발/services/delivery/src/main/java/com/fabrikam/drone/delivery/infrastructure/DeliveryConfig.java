package com.fabrikam.drone.delivery.infrastructure;

import com.fabrikam.drone.delivery.domain.EtaCalculator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.time.Duration;
import java.util.function.Consumer;

/** 배달 서비스 구성. */
@Configuration
public class DeliveryConfig {

    private static final Logger log = LoggerFactory.getLogger(DeliveryConfig.class);

    /**
     * 시계를 주입한다 — {@code Instant.now()} 를 직접 부르면 시간 의존 로직을 테스트할 수 없다.
     */
    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }

    @Bean
    @ConfigurationProperties(prefix = "drone.eta")
    public EtaProperties etaProperties() {
        return new EtaProperties();
    }

    @Bean
    public EtaCalculator etaCalculator(EtaProperties props) {
        return new EtaCalculator(props.getCruiseSpeedKmh(),
                Duration.ofSeconds(props.getFixedOverheadSeconds()));
    }

    /**
     * 이벤트 전송기 — 실제 Event Hubs 클라이언트를 여기에 연결한다.
     *
     * <p>본 산출물은 «실행하지 않음»이 전제이므로 로그 전송기를 기본값으로 둔다.
     * 실제 배포 시 {@code spring-cloud-azure-starter-integration-eventhubs} 의
     * {@code EventHubsTemplate} 을 주입하도록 교체한다.
     */
    @Bean
    public Consumer<EventHubsDeliveryEventPublisher.EventEnvelope> eventSender() {
        return env -> log.info("[이벤트 전송] hub={} key={} type={}",
                env.hubName(), env.partitionKey(), env.eventType());
    }

    /** ETA 계산 파라미터 — 코드가 아니라 구성으로 조정한다. */
    public static class EtaProperties {
        private double cruiseSpeedKmh = 60.0;
        private long fixedOverheadSeconds = 240;

        public double getCruiseSpeedKmh() { return cruiseSpeedKmh; }
        public void setCruiseSpeedKmh(double v) { this.cruiseSpeedKmh = v; }
        public long getFixedOverheadSeconds() { return fixedOverheadSeconds; }
        public void setFixedOverheadSeconds(long v) { this.fixedOverheadSeconds = v; }
    }
}
