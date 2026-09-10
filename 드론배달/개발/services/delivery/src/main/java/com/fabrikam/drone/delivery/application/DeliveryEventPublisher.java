package com.fabrikam.drone.delivery.application;

import com.fabrikam.drone.contract.event.DomainEvent;

/** 도메인 이벤트 발행 포트. 구현은 인프라(Event Hubs)에 있다. */
public interface DeliveryEventPublisher {
    void publish(DomainEvent event);
}
