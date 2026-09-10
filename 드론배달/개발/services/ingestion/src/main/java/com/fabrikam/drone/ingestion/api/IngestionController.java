package com.fabrikam.drone.ingestion.api;

import com.fabrikam.drone.contract.ErrorCodes;
import com.fabrikam.drone.contract.Headers;
import com.fabrikam.drone.contract.vo.*;
import com.fabrikam.drone.ingestion.application.IdempotencyGuard;
import com.fabrikam.drone.ingestion.application.IngestionService;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.net.URI;
import java.time.Instant;
import java.util.Optional;

/**
 * 배달 요청 접수 API — 공개.
 *
 * <h2>왜 201 이 아니라 202 인가</h2>
 * 요청을 <b>접수</b>했을 뿐 배달은 아직 만들어지지 않았다.
 * {@code 201 Created} 를 주면 클라이언트는 «생성됐다»고 믿고 바로 조회했다가 404 를 받는다.
 * {@code 202 Accepted} + {@code Location} + {@code Retry-After} 가
 * <b>비동기 요청‑회신 패턴</b>의 정확한 표현이다.
 */
@Tag(name = "Ingestion", description = "배달 요청 접수 (공개 API)")
@RestController
@RequestMapping("/api/v1/deliveries")
public class IngestionController {

    private final IngestionService service;
    private final IdempotencyGuard idempotency;
    private final ObjectMapper mapper;

    public IngestionController(IngestionService service, IdempotencyGuard idempotency,
                               ObjectMapper mapper) {
        this.service = service;
        this.idempotency = idempotency;
        this.mapper = mapper;
    }

    @Operation(summary = "배달 예약 요청 접수",
            description = """
                    요청을 큐에 넣고 즉시 202 를 반환한다 (목표 p95 ≤ 300ms).
                    실제 배달 생성은 비동기로 진행되므로 statusUrl 로 진행 상황을 확인한다.
                    Idempotency-Key 헤더가 필수이며, 같은 키로 재시도하면 같은 결과를 받는다.""")
    @ApiResponses({
            @ApiResponse(responseCode = "202", description = "접수 완료"),
            @ApiResponse(responseCode = "400", description = "요청 형식 오류 또는 멱등 키 누락"),
            @ApiResponse(responseCode = "422", description = "같은 멱등 키로 다른 내용을 보냄")
    })
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<?> create(
            @Parameter(description = "멱등 키 (UUID 권장)", required = true,
                    example = "550e8400-e29b-41d4-a716-446655440000")
            @RequestHeader(value = Headers.IDEMPOTENCY_KEY, required = false) String idempotencyKey,
            @Valid @RequestBody CreateDeliveryRequest request) throws Exception {

        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST,
                    "Idempotency-Key 헤더가 필요합니다.");
            p.setTitle("멱등 키 누락");
            p.setType(URI.create(ErrorCodes.IDEMPOTENCY_KEY_MISSING));
            return ResponseEntity.badRequest().body(p);
        }

        String canonicalBody = mapper.writeValueAsString(request);

        // 재시도라면 첫 응답을 그대로 돌려준다 — 두 번 처리하지 않는다.
        Optional<String> cached = idempotency.findExisting(idempotencyKey, canonicalBody);
        if (cached.isPresent()) {
            AcceptedResponse prior = mapper.readValue(cached.get(), AcceptedResponse.class);
            return accepted(prior);
        }

        String deliveryId = service.enqueue(
                request.ownerId(),
                new Location(request.pickup().latitude(), request.pickup().longitude(),
                        orZero(request.pickup().altitude())),
                new Location(request.dropoff().latitude(), request.dropoff().longitude(),
                        orZero(request.dropoff().altitude())),
                new TimeWindow(request.pickupWindow().earliest(), request.pickupWindow().latest()),
                new PackageWeight(request.packageInfo().weight(),
                        PackageWeight.WeightUnit.valueOf(request.packageInfo().unit())),
                request.packageInfo().size(),
                request.packageInfo().description(),
                MDC.get(Headers.MDC_CORRELATION_ID));

        AcceptedResponse response = new AcceptedResponse(deliveryId, "PENDING",
                "/api/v1/deliveries/%s/status".formatted(deliveryId),
                MDC.get(Headers.MDC_CORRELATION_ID));

        idempotency.remember(idempotencyKey, canonicalBody, mapper.writeValueAsString(response));
        return accepted(response);
    }

    @Operation(summary = "배달 취소 요청 접수")
    @ApiResponse(responseCode = "202", description = "취소 요청 접수")
    @DeleteMapping("/{deliveryId}")
    public ResponseEntity<AcceptedResponse> cancel(
            @PathVariable String deliveryId,
            @RequestParam(required = false) String reason) {
        service.enqueueCancellation(deliveryId, reason, MDC.get(Headers.MDC_CORRELATION_ID));
        return ResponseEntity.accepted().body(new AcceptedResponse(deliveryId, "CANCELLING",
                "/api/v1/deliveries/%s/status".formatted(deliveryId),
                MDC.get(Headers.MDC_CORRELATION_ID)));
    }

    private static ResponseEntity<AcceptedResponse> accepted(AcceptedResponse r) {
        return ResponseEntity.accepted()
                .location(URI.create("/api/v1/deliveries/" + r.deliveryId()))
                .header("Retry-After", "2")                 // 2초 뒤 조회를 권한다
                .body(r);
    }

    private static double orZero(Double v) {
        return v == null ? 0 : v;
    }

    // ─────────────────────────────────────────── DTO

    @Schema(description = "배달 예약 요청")
    public record CreateDeliveryRequest(
            @Schema(example = "acc-0001") @NotBlank String ownerId,
            @Valid @NotNull PointDto pickup,
            @Valid @NotNull PointDto dropoff,
            @Valid @NotNull WindowDto pickupWindow,
            @Valid @NotNull PackageDto packageInfo) {
    }

    @Schema(description = "좌표")
    public record PointDto(
            @NotNull @DecimalMin("-90.0") @DecimalMax("90.0") Double latitude,
            @NotNull @DecimalMin("-180.0") @DecimalMax("180.0") Double longitude,
            @DecimalMin("0.0") Double altitude) {
    }

    @Schema(description = "픽업 희망 시간대")
    public record WindowDto(@NotNull Instant earliest, @NotNull Instant latest) {
    }

    @Schema(description = "패키지 정보")
    public record PackageDto(
            @Schema(example = "2.5") @NotNull @DecimalMin("0.001") BigDecimal weight,
            @Schema(example = "KG", allowableValues = {"KG", "G"}) @NotBlank String unit,
            @NotNull PackageSize size,
            @Size(max = 200) String description) {
    }

    @Schema(description = "접수 확인")
    public record AcceptedResponse(String deliveryId, String status,
                                   String statusUrl, String correlationId) {
    }
}
