package com.fabrikam.drone.delivery.api;

import com.fabrikam.drone.contract.Headers;
import com.fabrikam.drone.contract.vo.TimeWindow;
import com.fabrikam.drone.delivery.api.dto.Dtos.AssignDroneRequest;
import com.fabrikam.drone.delivery.api.dto.Dtos.ConfirmRequest;
import com.fabrikam.drone.delivery.api.dto.Dtos.DeliveryResponse;
import com.fabrikam.drone.delivery.api.dto.Dtos.DeliveryStatusResponse;
import com.fabrikam.drone.delivery.api.dto.Dtos.UpsertDeliveryRequest;
import com.fabrikam.drone.delivery.application.DeliveryAppService;
import com.fabrikam.drone.delivery.domain.Delivery;
import com.fabrikam.drone.delivery.domain.DeliveryId;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * 배달 REST API.
 *
 * <h2>공개 / 내부 구분</h2>
 * <ul>
 *   <li>공개 — {@code GET /{id}}, {@code GET /{id}/status} (사용자 조회)</li>
 *   <li>내부 — {@code PUT}, {@code DELETE}, {@code POST /confirmation} (Workflow 만 호출)</li>
 * </ul>
 * 내부 엔드포인트는 게이트웨이 라우팅에서 외부에 노출하지 않는다.
 */
@Tag(name = "Deliveries", description = "배달 상태 · 추적 · 수명 주기")
@RestController
@RequestMapping("/api/v1/deliveries")
public class DeliveryController {

    private final DeliveryAppService service;

    public DeliveryController(DeliveryAppService service) {
        this.service = service;
    }

    @Operation(summary = "배달 생성 또는 갱신 (내부 · 멱등)",
            description = "PUT 이므로 Workflow 가 재시도해도 배달이 두 번 생성되지 않는다.")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "생성 또는 기존 반환"),
            @ApiResponse(responseCode = "400", description = "요청 형식 오류",
                    content = @Content(schema = @Schema(ref = "#/components/schemas/ProblemDetail")))
    })
    @PutMapping("/{id}")
    public DeliveryResponse upsert(
            @Parameter(description = "배달 ID", example = "dlv-7f3a9c") @PathVariable String id,
            @Valid @RequestBody UpsertDeliveryRequest request,
            @RequestHeader(value = Headers.CORRELATION_ID, required = false) String correlationId) {

        Delivery d = service.upsert(
                DeliveryId.of(id), request.ownerId(), request.packageId(),
                request.pickup().toDomain(), request.dropoff().toDomain(),
                new TimeWindow(request.pickupWindow().earliest(), request.pickupWindow().latest()),
                correlationId);
        return DeliveryResponse.from(d);
    }

    @Operation(summary = "배달 상세 조회")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "조회 성공"),
            @ApiResponse(responseCode = "404", description = "배달 없음")
    })
    @GetMapping("/{id}")
    public DeliveryResponse get(@PathVariable String id) {
        return DeliveryResponse.from(service.get(DeliveryId.of(id)));
    }

    @Operation(summary = "배달 상태 조회 (추적 화면 전용)",
            description = "필요한 필드만 담은 경량 응답. 목표 p95 ≤ 150 ms (NFR-02).")
    @ApiResponse(responseCode = "200", description = "조회 성공")
    @GetMapping("/{id}/status")
    public DeliveryStatusResponse getStatus(@PathVariable String id) {
        return DeliveryStatusResponse.from(service.get(DeliveryId.of(id)));
    }

    @Operation(summary = "계정별 배달 목록")
    @GetMapping
    public List<DeliveryResponse> listByOwner(
            @RequestParam String ownerId,
            @RequestParam(defaultValue = "20") int limit) {
        return service.findByOwner(ownerId, Math.min(limit, 100))
                .stream().map(DeliveryResponse::from).toList();
    }

    @Operation(summary = "드론 할당 (내부)")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "할당 성공"),
            @ApiResponse(responseCode = "409", description = "허용되지 않는 상태 전이")
    })
    @PutMapping("/{id}/drone")
    public DeliveryResponse assignDrone(
            @PathVariable String id,
            @Valid @RequestBody AssignDroneRequest request,
            @RequestHeader(value = Headers.CORRELATION_ID, required = false) String correlationId) {
        return DeliveryResponse.from(
                service.assignDrone(DeliveryId.of(id), request.droneId(), correlationId));
    }

    @Operation(summary = "수령 확인 · 배달 완료 (내부)")
    @PostMapping("/{id}/confirmation")
    public DeliveryResponse confirm(
            @PathVariable String id,
            @Valid @RequestBody ConfirmRequest request,
            @RequestHeader(value = Headers.CORRELATION_ID, required = false) String correlationId) {
        return DeliveryResponse.from(service.complete(
                DeliveryId.of(id), request.signatureRef(),
                request.confirmedAt() == null ? null : request.confirmedAt().toDomain(),
                correlationId));
    }

    @Operation(summary = "배달 취소",
            description = "INV-01 — IN_TRANSIT 이후에는 취소할 수 없다 (409).")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "취소 성공"),
            @ApiResponse(responseCode = "409", description = "이미 이동을 시작해 취소 불가"),
            @ApiResponse(responseCode = "404", description = "배달 없음")
    })
    @DeleteMapping("/{id}")
    public DeliveryResponse cancel(
            @PathVariable String id,
            @RequestParam(required = false) String reason,
            @RequestHeader(value = Headers.CORRELATION_ID, required = false) String correlationId) {
        return DeliveryResponse.from(service.cancel(DeliveryId.of(id), reason, correlationId));
    }

    @Operation(summary = "배달 삭제 (보상 트랜잭션 전용 · 내부)",
            description = "이미 없어도 204 를 반환한다 — 보상은 멱등해야 하기 때문이다.")
    @ApiResponse(responseCode = "204", description = "삭제 완료 또는 대상 없음")
    @DeleteMapping("/{id}/compensate")
    public ResponseEntity<Void> compensate(@PathVariable String id) {
        service.delete(DeliveryId.of(id));
        return ResponseEntity.noContent().build();
    }
}
