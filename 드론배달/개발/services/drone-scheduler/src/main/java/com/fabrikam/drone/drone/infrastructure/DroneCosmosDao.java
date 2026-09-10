package com.fabrikam.drone.drone.infrastructure;

import com.azure.spring.data.cosmos.repository.CosmosRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/**
 * Spring Data Cosmos 저장소.
 *
 * <p>도메인 계층의 {@code DroneRepository} 와 이름이 비슷하지만 역할이 다르다 —
 * 이것은 <b>인프라 세부</b>이고, 도메인은 이 인터페이스를 모른다.
 */
@Repository
public interface DroneCosmosDao extends CosmosRepository<DroneDocument, String> {
    Optional<DroneDocument> findByDroneId(String droneId);
}
