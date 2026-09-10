package com.fabrikam.drone.drone.domain;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

/**
 * 드론 저장소 — 포트.
 *
 * <p>{@link #saveIfMatch} 가 INV-03 의 «최종 방어선»이다.
 * 애그리거트의 검사만으로는 «서로 다른 인스턴스가 동시에 같은 드론을 읽은» 경우를 막지 못한다.
 * 저장 시점의 조건부 쓰기(ETag)가 둘 중 하나를 실패시킨다.
 */
public interface DroneRepository {

    Optional<Drone> findById(DroneId id);

    Drone insert(Drone drone);

    /**
     * 조건부 저장 — 로드 시점의 etag 와 저장 시점의 etag 가 같을 때만 성공한다.
     *
     * @throws OptimisticConcurrencyException 그사이 다른 요청이 변경했을 때
     */
    Drone saveIfMatch(Drone drone, String expectedEtag);

    /**
     * 할당 가능한 드론 후보를 찾는다.
     *
     * <p>⚠️ 이 결과는 «힌트»다. 조회와 할당 사이에 다른 요청이 가져갈 수 있으므로
     * 반드시 {@link #saveIfMatch} 로 최종 확정해야 한다.
     */
    List<DroneId> findAvailableCandidates(BigDecimal requiredKg, int limit);

    /** 낙관적 동시성 충돌 — 재시도 대상이다. */
    class OptimisticConcurrencyException extends RuntimeException {
        public OptimisticConcurrencyException(DroneId id) {
            super("드론 %s 가 그사이 변경되었습니다.".formatted(id));
        }
    }
}
