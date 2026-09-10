package com.fabrikam.drone.delivery.api;

import com.fabrikam.drone.contract.Headers;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

/**
 * 상관 ID 전파 필터 — OPS-04 (요청 1건의 서비스 횡단 추적 100 %).
 *
 * <p>헤더에 있으면 이어받고, 없으면 만든다. MDC 에 넣으면 구조화 로그 패턴이
 * 자동으로 모든 로그 줄에 포함시킨다.
 */
@Component
@Order(1)
public class CorrelationIdFilter extends OncePerRequestFilter {

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String correlationId = request.getHeader(Headers.CORRELATION_ID);
        if (correlationId == null || correlationId.isBlank()) {
            correlationId = UUID.randomUUID().toString();
        }
        MDC.put(Headers.MDC_CORRELATION_ID, correlationId);
        response.setHeader(Headers.CORRELATION_ID, correlationId);
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.clear();                     // ★ 스레드 재사용 시 이전 요청의 ID 가 새어 나가지 않게
        }
    }
}
