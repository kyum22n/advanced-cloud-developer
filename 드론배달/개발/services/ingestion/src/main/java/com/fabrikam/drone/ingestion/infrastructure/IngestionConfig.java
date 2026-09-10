package com.fabrikam.drone.ingestion.infrastructure;

import com.fabrikam.drone.contract.Headers;
import com.fabrikam.drone.ingestion.application.QueuePublisher;
import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/** Ingestion 구성. */
@Configuration
public class IngestionConfig {

    private static final Logger log = LoggerFactory.getLogger(IngestionConfig.class);

    /**
     * 큐 게시기 — 실제 배포 시 Service Bus 클라이언트로 교체한다.
     *
     * <p>본 산출물은 «실행하지 않음»이 전제이므로 로그 게시기를 기본값으로 둔다.
     * 실제로는 {@code ServiceBusSenderClient} 를 주입하고,
     * {@code setMessageId(messageId)} 로 중복 감지를,
     * {@code getApplicationProperties().put("correlationId", ...)} 로 추적 전파를 수행한다.
     */
    @Bean
    public QueuePublisher queuePublisher() {
        return (messageId, body, correlationId) ->
                log.info("[큐 게시] messageId={} correlationId={}", messageId, correlationId);
    }

    /** 상관 ID 필터 — 없으면 여기서 생성한다. */
    @Component
    @Order(1)
    public static class CorrelationIdFilter extends OncePerRequestFilter {

        @Override
        protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                        FilterChain chain) throws IOException,
                jakarta.servlet.ServletException {
            String id = request.getHeader(Headers.CORRELATION_ID);
            if (id == null || id.isBlank()) {
                id = UUID.randomUUID().toString();
            }
            MDC.put(Headers.MDC_CORRELATION_ID, id);
            response.setHeader(Headers.CORRELATION_ID, id);
            try {
                chain.doFilter(request, response);
            } finally {
                MDC.clear();
            }
        }
    }
}
