package com.fabrikam.drone.drone.api;

import com.fabrikam.drone.contract.Headers;
import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.drone.application.DroneAppService;
import com.fabrikam.drone.drone.domain.Drone;
import com.fabrikam.drone.drone.domain.DroneId;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * 드론 REST API.
 *
 * <p>할당 엔드포인트가 {@code PUT /assignments/{deliveryId}} 인 이유 —
 * 「이 배달의 드론 할당」이라는 리소스는 배달마다 하나뿐이므로 PUT 이 자연스럽고,
 * <b>재시도해도 드론이 두 대 할당되지 않는다</b>.
 * {@code POST /assign} 이었다면 재시도가 곧 이중 할당이다.
 */
@Tag(name = "Drones", description = "드론 할당 · 텔레메트리")
@RestController
@RequestMapping("/api/v1/drones")
public class DroneController {

    private final DroneAppService service;

    public DroneController(DroneAppService service) {
        this.service = service;
    }

    @Operation(summary = "배달에 드론 할당 (내부 · 멱등)",
            description = "가용 드론이 없으면 409 를 반환하고, Workflow 가 타사 위탁으로 전환한다.")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "할당 성공"),
            @ApiResponse(responseCode = "409", description = "가용 드론 없음 또는 이미 점유됨")
    })
    @PutMapping("/assignments/{deliveryId}")
    public AssignmentResponse assign(
            @Parameter(description = "배달 ID", example = "dlv-7f3a9c") @PathVariable String deliveryId,
            @Valid @RequestBody AssignRequest request,
            @RequestHeader(value = Headers.CORRELATION_ID, required = false) String correlationId) {

        Drone drone = service.assign(deliveryId, request.requiredCapacityKg(), correlationId);
        return new AssignmentResponse(deliveryId, drone.id().value(), drone.updatedAt());
    }

    @Operation(summary = "드론 할당 해제 (보상 트랜잭션 · 내부)",
            description = "대상이 없어도 204 를 반환한다 — 보상은 멱등해야 하기 때문이다.")
    @ApiResponse(responseCode = "204", description = "해제 완료 또는 대상 없음")
    @DeleteMapping("/assignments/{deliveryId}")
    public ResponseEntity<Void> release(
            @PathVariable String deliveryId,
            @RequestHeader(value = Headers.CORRELATION_ID, required = false) String correlationId) {
        service.releaseByDelivery(deliveryId, correlationId);
        return ResponseEntity.noContent().build();
    }

    @Operation(summary = "드론 텔레메트리 보고 (드론 디바이스)",
            description = "위치·배터리를 보고한다. DroneStatusChanged 이벤트가 발행된다.")
    @PostMapping("/{droneId}/telemetry")
    public DroneResponse telemetry(
            @PathVariable String droneId,
            @Valid @RequestBody TelemetryRequest request,
            @RequestHeader(value = Headers.CORRELATION_ID, required = false) String correlationId) {

        Drone d = service.reportTelemetry(DroneId.of(droneId),
                new Location(request.latitude(), request.longitude(),
                        request.altitude() == null ? 0 : request.altitude()),
                request.batteryPercent(), correlationId);
        return DroneResponse.from(d);
    }

    @Operation(summary = "드론 상태 조회 (내부)")
    @GetMapping("/{droneId}")
    public DroneResponse get(@PathVariable String droneId) {
        return DroneResponse.from(service.get(DroneId.of(droneId)));
    }

    @Operation(summary = "드론 등록 (운영)")
    @PostMapping
    public DroneResponse register(@Valid @RequestBody RegisterRequest request) {
        return DroneResponse.from(service.register(DroneId.of(request.droneId()),
                request.capacityKg(),
                new Location(request.latitude(), request.longitude(), 0)));
    }

    // ─────────────────────────────────────────── DTO

    @Schema(description = "드론 할당 요청")
    public record AssignRequest(
            @Schema(description = "필요 적재 용량(kg)", example = "2.5")
            @NotNull @DecimalMin("0.001") BigDecimal requiredCapacityKg) {
    }

    @Schema(description = "드론 할당 결과")
    public record AssignmentResponse(String deliveryId, String droneId, Instant assignedAt) {
    }

    @Schema(description = "텔레메트리 보고")
    public record TelemetryRequest(
            @NotNull @DecimalMin("-90.0") @DecimalMax("90.0") Double latitude,
            @NotNull @DecimalMin("-180.0") @DecimalMax("180.0") Double longitude,
            @DecimalMin("0.0") Double altitude,
            @Schema(description = "배터리 잔량(%)", example = "82")
            @NotNull @Min(0) @Max(100) Integer batteryPercent) {
    }

    @Schema(description = "드론 등록 요청")
    public record RegisterRequest(
            @NotBlank String droneId,
            @NotNull @DecimalMin("0.001") BigDecimal capacityKg,
            @NotNull Double latitude,
            @NotNull Double longitude) {
    }

    @Schema(description = "드론 상태")
    public record DroneResponse(String droneId, String status, Double latitude, Double longitude,
                                Double altitude, int batteryPercent, String currentDeliveryId,
                                Instant updatedAt) {

        public static DroneResponse from(Drone d) {
            Location l = d.currentLocation();
            return new DroneResponse(d.id().value(), d.status().name(),
                    l == null ? null : l.latitude(), l == null ? null : l.longitude(),
                    l == null ? null : l.altitude(), d.batteryPercent(),
                    d.currentDeliveryId().orElse(null), d.updatedAt());
        }
    }
}
