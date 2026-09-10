package com.fabrikam.drone.history.domain;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

/**
 * 이력 저장소 — 포트.
 *
 * <p>핫(Cosmos DB · 30일 TTL)과 콜드(Data Lake · 무기한)를 이 인터페이스 뒤에 감춘다.
 * 호출자는 «어디에 있는지» 알 필요가 없다.
 */
public interface DeliveryHistoryRepository {

    Optional<DeliveryHistoryEntry> findById(String deliveryId);

    void save(DeliveryHistoryEntry entry);

    /** 기간·계정으로 조회한다. 페이징 필수 — 전체를 한 번에 읽으면 메모리가 터진다. */
    List<DeliveryHistoryEntry> findByPeriod(String ownerId, Instant from, Instant to,
                                            int page, int size);

    /** 월간 집계 — 구체화된 뷰. */
    Summary summarize(String ownerId, Instant from, Instant to);

    /**
     * @param completed 완료 건수
     * @param cancelled 취소 건수
     * @param failed    실패 건수
     * @param averageDurationSeconds 평균 소요 시간(완료 건만)
     */
    record Summary(long completed, long cancelled, long failed, double averageDurationSeconds) {
    }
}
