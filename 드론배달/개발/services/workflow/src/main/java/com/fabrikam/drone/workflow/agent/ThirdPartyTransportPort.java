package com.fabrikam.drone.workflow.agent;

import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.contract.vo.PackageWeight;

import java.util.Optional;

/**
 * 타사 운송 — 포트 (손상 방지 계층의 «우리 쪽 면»).
 *
 * <p>이 인터페이스에는 외부 시스템의 용어({@code ref_no}, {@code stat_cd} 등)가
 * <b>하나도 나타나지 않는다</b>. 그것이 손상 방지 계층의 목적이다.
 */
public interface ThirdPartyTransportPort {

    /**
     * 배달을 타사에 위탁한다.
     *
     * @return 외부 추적 번호. 위탁에 실패하면 {@link Optional#empty()}
     */
    Optional<String> delegate(String deliveryId, Location pickup, Location dropoff,
                              PackageWeight weight, String correlationId);
}
