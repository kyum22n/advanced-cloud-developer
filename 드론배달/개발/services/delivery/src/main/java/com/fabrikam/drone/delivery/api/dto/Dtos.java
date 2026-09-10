package com.fabrikam.drone.delivery.api.dto;

import com.fabrikam.drone.contract.vo.DeliveryStatus;
import com.fabrikam.drone.contract.vo.Eta;
import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.delivery.domain.Delivery;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.Instant;

/**
 * API 표현 — 도메인 모델을 그대로 노출하지 않는다.
 *
 * <p>도메인 모델을 REST 로 그대로 내보내면, 내부 리팩터링이 곧 API 파괴 변경이 된다.
 * DTO 를 하나 두는 비용으로 «내부는 자유롭게 바꾸고 계약은 지키는» 상태를 얻는다.
 */
public final class Dtos {

    private Dtos() {
    }

    @Schema(description = "위치")
    public record LocationDto(
            @Schema(description = "위도", example = "37.5665")
            @NotNull @DecimalMin("-90.0") @DecimalMax("90.0") Double latitude,
            @Schema(description = "경도", example = "126.9780")
            @NotNull @DecimalMin("-180.0") @DecimalMax("180.0") Double longitude,
            @Schema(description = "고도(m)", example = "0")
            @DecimalMin("0.0") Double altitude) {

        public Location toDomain() {
            return new Location(latitude, longitude, altitude == null ? 0 : altitude);
        }

        public static LocationDto from(Location l) {
            return l == null ? null : new LocationDto(l.latitude(), l.longitude(), l.altitude());
        }
    }

    @Schema(description = "시간 구간")
    public record TimeWindowDto(
            @Schema(example = "2026-08-29T10:00:00Z") @NotNull Instant earliest,
            @Schema(example = "2026-08-29T11:00:00Z") @NotNull Instant latest) {
    }

    @Schema(description = "배달 생성·갱신 요청 (내부 API · 멱등)")
    public record UpsertDeliveryRequest(
            @Schema(description = "소유 계정 ID", example = "acc-0001")
            @NotBlank String ownerId,
            @Schema(description = "패키지 ID", example = "pkg-3c9e1a")
            @NotBlank String packageId,
            @Valid @NotNull LocationDto pickup,
            @Valid @NotNull LocationDto dropoff,
            @Valid @NotNull TimeWindowDto pickupWindow) {
    }

    @Schema(description = "드론 할당 요청")
    public record AssignDroneRequest(
            @Schema(example = "drn-0042") @NotBlank String droneId) {
    }

    @Schema(description = "수령 확인 요청")
    public record ConfirmRequest(
            @Schema(description = "서명 이미지 참조") String signatureRef,
            @Valid LocationDto confirmedAt) {
    }

    @Schema(description = "배달 상세")
    public record DeliveryResponse(
            String deliveryId, String ownerId, String packageId, String droneId,
            DeliveryStatus status, LocationDto pickup, LocationDto dropoff,
            LocationDto currentLocation, Eta eta,
            Instant createdAt, Instant updatedAt, long version) {

        public static DeliveryResponse from(Delivery d) {
            return new DeliveryResponse(
                    d.id().value(), d.ownerId(), d.packageId(), d.droneId(), d.status(),
                    LocationDto.from(d.pickup()), LocationDto.from(d.dropoff()),
                    LocationDto.from(d.currentLocation()), d.eta(),
                    d.createdAt(), d.updatedAt(), d.version());
        }
    }

    @Schema(description = "배달 상태 (추적 화면 전용 경량 응답)")
    public record DeliveryStatusResponse(
            @Schema(example = "dlv-7f3a9c") String deliveryId,
            DeliveryStatus status,
            LocationDto droneLocation,
            Eta eta,
            Instant updatedAt) {

        public static DeliveryStatusResponse from(Delivery d) {
            return new DeliveryStatusResponse(d.id().value(), d.status(),
                    LocationDto.from(d.currentLocation()), d.eta(), d.updatedAt());
        }
    }
}
