package com.fabrikam.drone.history.api;

import com.fabrikam.drone.history.application.HistoryEventHandler;
import com.fabrikam.drone.history.domain.DeliveryHistoryEntry;
import com.fabrikam.drone.history.domain.DeliveryHistoryRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.List;
import java.util.NoSuchElementException;

/**
 * 이력 조회 API — CQRS 읽기 측.
 *
 * <p>쓰기 API 가 없다. 이력은 <b>이벤트로만</b> 만들어진다.
 * 누군가 이력을 직접 고칠 수 있다면 그것은 이미 «기록»이 아니다.
 */
@Tag(name = "History", description = "배달 이력 조회 · 집계")
@RestController
@RequestMapping("/api/v1/history")
public class HistoryController {

    private static final int MAX_PAGE_SIZE = 100;

    private final DeliveryHistoryRepository repository;
    private final HistoryEventHandler handler;

    public HistoryController(DeliveryHistoryRepository repository, HistoryEventHandler handler) {
        this.repository = repository;
        this.handler = handler;
    }

    @Operation(summary = "배달 이력 상세 조회")
    @ApiResponse(responseCode = "200", description = "조회 성공")
    @ApiResponse(responseCode = "404", description = "이력 없음")
    @GetMapping("/{deliveryId}")
    public HistoryResponse get(
            @Parameter(example = "dlv-7f3a9c") @PathVariable String deliveryId) {
        return HistoryResponse.from(handler.find(deliveryId)
                .orElseThrow(() -> new NoSuchElementException("이력을 찾을 수 없습니다: " + deliveryId)));
    }

    @Operation(summary = "기간·계정별 이력 목록",
            description = "페이징 필수. 한 번에 최대 100건까지 조회한다.")
    @GetMapping
    public List<HistoryResponse> list(
            @RequestParam String ownerId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant from,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant to,
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(MAX_PAGE_SIZE) int size) {

        return repository.findByPeriod(ownerId, from, to, page, Math.min(size, MAX_PAGE_SIZE))
                .stream().map(HistoryResponse::from).toList();
    }

    @Operation(summary = "기간 집계",
            description = "완료·취소·실패 건수와 평균 소요 시간. 구체화된 뷰에서 읽는다.")
    @GetMapping("/summary")
    public DeliveryHistoryRepository.Summary summary(
            @RequestParam String ownerId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant from,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant to) {
        return repository.summarize(ownerId, from, to);
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ProblemDetail onNotFound(NoSuchElementException e) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        p.setTitle("이력을 찾을 수 없습니다");
        return p;
    }

    @Schema(description = "배달 이력")
    public record HistoryResponse(String deliveryId, String ownerId, String packageId,
                                  String droneId, String finalStatus, Instant createdAt,
                                  Instant completedAt, String failureReason,
                                  long durationSeconds, List<MilestoneDto> milestones) {

        public static HistoryResponse from(DeliveryHistoryEntry e) {
            return new HistoryResponse(e.deliveryId(), e.ownerId(), e.packageId(), e.droneId(),
                    e.finalStatus(), e.createdAt(), e.completedAt(), e.failureReason(),
                    e.durationSeconds(),
                    e.milestones().stream()
                            .map(m -> new MilestoneDto(m.eventType(), m.occurredAt(), m.status()))
                            .toList());
        }
    }

    @Schema(description = "이정표")
    public record MilestoneDto(String eventType, Instant occurredAt, String status) {
    }
}
