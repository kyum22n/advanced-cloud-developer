package com.fabrikam.drone.delivery.domain;

import java.time.Instant;

/** 알림 발송 이력 — Delivery 애그리거트의 하위 엔터티. */
public record Notification(String notificationId,
                           String channel,
                           String messageKey,
                           Instant sentAt) {
}
