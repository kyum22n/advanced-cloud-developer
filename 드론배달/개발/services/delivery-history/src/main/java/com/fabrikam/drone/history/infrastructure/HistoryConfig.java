package com.fabrikam.drone.history.infrastructure;

import com.fabrikam.drone.history.application.HistoryEventHandler;
import com.fabrikam.drone.history.domain.DeliveryHistoryEntry;
import com.fabrikam.drone.history.domain.DeliveryHistoryRepository;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Repository;

import java.time.Duration;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 이력 서비스 구성.
 *
 * <p>⚠️ 기본 구현은 메모리다. 실제 배포 시 핫(Cosmos DB)·콜드(Data Lake) 구현으로 교체한다.
 * 본 산출물은 «실행하지 않음»이 전제이므로, 서비스가 기동하고 계약 테스트가 돌 최소 구현을 둔다.
 */
@Configuration
public class HistoryConfig {

    @Repository
    public static class InMemoryHistoryRepository implements DeliveryHistoryRepository {

        private final Map<String, DeliveryHistoryEntry> store = new ConcurrentHashMap<>();

        @Override
        public Optional<DeliveryHistoryEntry> findById(String deliveryId) {
            return Optional.ofNullable(store.get(deliveryId));
        }

        @Override
        public void save(DeliveryHistoryEntry entry) {
            store.put(entry.deliveryId(), entry);
        }

        @Override
        public List<DeliveryHistoryEntry> findByPeriod(String ownerId, Instant from, Instant to,
                                                       int page, int size) {
            List<DeliveryHistoryEntry> matched = store.values().stream()
                    .filter(e -> ownerId == null || ownerId.equals(e.ownerId()))
                    .filter(e -> e.createdAt() != null
                            && !e.createdAt().isBefore(from) && !e.createdAt().isAfter(to))
                    .sorted(Comparator.comparing(DeliveryHistoryEntry::createdAt).reversed())
                    .toList();

            int start = Math.min(page * size, matched.size());
            int end = Math.min(start + size, matched.size());
            return matched.subList(start, end);
        }

        @Override
        public Summary summarize(String ownerId, Instant from, Instant to) {
            List<DeliveryHistoryEntry> all = findByPeriod(ownerId, from, to, 0, Integer.MAX_VALUE);
            long completed = all.stream().filter(e -> "COMPLETED".equals(e.finalStatus())).count();
            long cancelled = all.stream().filter(e -> "CANCELLED".equals(e.finalStatus())).count();
            long failed    = all.stream().filter(e -> "FAILED".equals(e.finalStatus())).count();
            double avg = all.stream()
                    .filter(e -> "COMPLETED".equals(e.finalStatus()))
                    .mapToLong(DeliveryHistoryEntry::durationSeconds)
                    .filter(d -> d >= 0)
                    .average().orElse(0.0);
            return new Summary(completed, cancelled, failed, avg);
        }
    }

    /**
     * 중복 제거 저장소 — 메모리 구현.
     *
     * <p>실제 배포 시 Redis {@code SET NX EX} 로 교체한다.
     * 인스턴스가 여러 개면 메모리 구현으로는 중복이 걸러지지 않는다 —
     * 이 한계를 알고 쓰는 것과 모르고 쓰는 것은 다르다.
     */
    @Bean
    public HistoryEventHandler.ProcessedEventStore processedEventStore() {
        Set<String> seen = ConcurrentHashMap.newKeySet();
        return (eventId, ttl) -> seen.add(eventId);
    }
}
