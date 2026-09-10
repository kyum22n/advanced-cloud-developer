package com.fabrikam.drone.delivery.domain;

import java.util.List;
import java.util.Optional;

/**
 * 배달 저장소 — 도메인 계층의 «포트».
 *
 * <p>인터페이스는 도메인에, 구현은 인프라에 둔다(의존성 역전).
 * 도메인이 Redis 를 알면 저장소를 바꿀 때 도메인을 고쳐야 한다.
 *
 * <p>애그리거트 루트 단위로만 존재한다 — {@code ConfirmationRepository} 는 만들지 않는다.
 */
public interface DeliveryRepository {

    Optional<Delivery> findById(DeliveryId id);

    /**
     * 저장한다. 낙관적 동시성 — 로드한 버전과 저장 시점 버전이 다르면 실패한다.
     *
     * @throws ConcurrencyConflictException 다른 요청이 먼저 갱신했을 때
     */
    Delivery save(Delivery delivery, long expectedVersion);

    /** 신규 저장 (버전 검사 없음). */
    Delivery insert(Delivery delivery);

    void deleteById(DeliveryId id);

    List<Delivery> findByOwner(String ownerId, int limit);

    /** 낙관적 동시성 충돌. HTTP 412 로 매핑된다. */
    class ConcurrencyConflictException extends RuntimeException {
        public ConcurrencyConflictException(DeliveryId id, long expected) {
            super("배달 %s 가 그사이 변경되었습니다. 기대한 버전: %d".formatted(id, expected));
        }
    }
}
