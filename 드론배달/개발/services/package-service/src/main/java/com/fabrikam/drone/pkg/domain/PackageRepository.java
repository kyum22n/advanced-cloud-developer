package com.fabrikam.drone.pkg.domain;

import java.util.Optional;

/** 패키지 저장소 — 포트. */
public interface PackageRepository {

    Optional<PackageAggregate> findById(PackageAggregate.PackageId id);

    PackageAggregate save(PackageAggregate aggregate);

    /** 보상 트랜잭션용. 이미 없어도 예외를 던지지 않는다. */
    void deleteById(PackageAggregate.PackageId id);
}
