package com.fabrikam.drone.pkg.infrastructure;

import com.fabrikam.drone.pkg.domain.PackageAggregate;
import com.fabrikam.drone.pkg.domain.PackageAggregate.PackageId;
import com.fabrikam.drone.pkg.domain.PackageRepository;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Repository;

import java.time.Clock;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 패키지 서비스 구성.
 *
 * <p>⚠️ 기본 저장소는 메모리 구현이다. 실제 배포 시 Cosmos DB for MongoDB 구현으로 교체한다.
 * 본 산출물은 «실행하지 않음»이 전제이므로, 실행 가능한 최소 구현을 두어
 * 서비스가 기동하고 계약 테스트가 돌 수 있게 한다.
 *
 * <p>MongoDB 구현 시 유의점 — Cosmos DB for MongoDB 의 인증은 NoSQL API 와 경로가 다르다.
 * 워크로드 ID 로 완전히 대체되지 않으면 Key Vault 를 2순위 수단으로 쓴다.
 * (설계/06_데이터_설계서.md §8.3 참조)
 */
@Configuration
public class PackageConfig {

    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }

    @Repository
    public static class InMemoryPackageRepository implements PackageRepository {

        private final Map<String, PackageAggregate> store = new ConcurrentHashMap<>();

        @Override
        public Optional<PackageAggregate> findById(PackageId id) {
            return Optional.ofNullable(store.get(id.value()));
        }

        @Override
        public PackageAggregate save(PackageAggregate aggregate) {
            store.put(aggregate.id().value(), aggregate);
            return aggregate;
        }

        @Override
        public void deleteById(PackageId id) {
            store.remove(id.value());          // 없어도 조용히 성공 — 보상 멱등성
        }
    }
}
