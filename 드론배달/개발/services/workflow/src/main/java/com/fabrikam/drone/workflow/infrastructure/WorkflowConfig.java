package com.fabrikam.drone.workflow.infrastructure;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.web.client.RestClient;

import java.time.Clock;
import java.time.Duration;

/**
 * Workflow 구성.
 *
 * <h2>서비스 검색</h2>
 * URL 을 하드코딩하지 않고 <b>논리 이름</b>을 쓴다. Azure Spring Apps 의
 * 서비스 레지스트리(Eureka)가 실제 인스턴스로 해석하고 부하를 분산한다.
 * 하드코딩하면 환경마다 URL 이 다르고 인스턴스 변화에 대응할 수 없다.
 *
 * <h2>시간 제한 예산</h2>
 * 전체 예산(큐 메시지 처리 30초) 안에서 각 호출의 몫을 미리 나눈다.
 * 시간 제한이 없는 호출은 장애를 그대로 전파한다.
 */
@Configuration
@EnableScheduling
public class WorkflowConfig {

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }

    @Bean
    public RestClient accountRestClient(
            @Value("${drone.services.account:http://account-service}") String baseUrl) {
        return build(baseUrl, Duration.ofSeconds(1), Duration.ofSeconds(1));
    }

    @Bean
    public RestClient packageRestClient(
            @Value("${drone.services.package:http://package-service}") String baseUrl) {
        return build(baseUrl, Duration.ofSeconds(1), Duration.ofSeconds(4));
    }

    @Bean
    public RestClient droneRestClient(
            @Value("${drone.services.drone:http://drone-service}") String baseUrl) {
        return build(baseUrl, Duration.ofSeconds(1), Duration.ofSeconds(7));
    }

    @Bean
    public RestClient deliveryRestClient(
            @Value("${drone.services.delivery:http://delivery-service}") String baseUrl) {
        return build(baseUrl, Duration.ofSeconds(1), Duration.ofSeconds(4));
    }

    /** 외부 — 가장 관대한 시간 제한. 대신 회로 차단기를 가장 빨리 연다. */
    @Bean
    public RestClient thirdPartyRestClient(
            @Value("${drone.services.thirdparty:https://api.thirdparty-transport.example}")
            String baseUrl) {
        return build(baseUrl, Duration.ofSeconds(2), Duration.ofSeconds(8));
    }

    private static RestClient build(String baseUrl, Duration connect, Duration read) {
        var factory = new org.springframework.http.client.SimpleClientHttpRequestFactory();
        factory.setConnectTimeout((int) connect.toMillis());
        factory.setReadTimeout((int) read.toMillis());
        return RestClient.builder().baseUrl(baseUrl).requestFactory(factory).build();
    }
}
