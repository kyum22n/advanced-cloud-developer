package com.fabrikam.drone.workflow.agent;

import com.fabrikam.drone.contract.vo.PackageSize;
import com.fabrikam.drone.contract.vo.PackageWeight;

/** 패키지 서비스 에이전트 — 포트. */
public interface PackageAgent {

    /** 패키지를 등록한다 (멱등 · PUT). */
    String register(String packageId, PackageWeight weight, PackageSize size,
                    String description, String correlationId);

    /** 보상 — 패키지를 삭제한다. 이미 없어도 성공으로 본다. */
    void delete(String packageId, String correlationId);
}
