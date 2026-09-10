package com.fabrikam.drone.pkg.api;

import com.fabrikam.drone.contract.ErrorCodes;
import com.fabrikam.drone.contract.Headers;
import com.fabrikam.drone.contract.vo.PackageSize;
import com.fabrikam.drone.contract.vo.PackageWeight;
import com.fabrikam.drone.pkg.domain.PackageAggregate;
import com.fabrikam.drone.pkg.domain.PackageAggregate.PackageId;
import com.fabrikam.drone.pkg.domain.PackageRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.math.BigDecimal;
import java.net.URI;
import java.time.Clock;
import java.time.Instant;
import java.util.List;
import java.util.NoSuchElementException;

/**
 * 패키지 API — 내부 전용.
 *
 * <p>{@code PUT} 을 쓰므로 Workflow 의 재시도가 패키지를 두 번 만들지 않는다.
 */
@Tag(name = "Packages", description = "패키지 등록 · 조회 (내부 API)")
@RestController
@RequestMapping("/api/v1/packages")
public class PackageController {

    private final PackageRepository repository;
    private final Clock clock;

    public PackageController(PackageRepository repository, Clock clock) {
        this.repository = repository;
        this.clock = clock;
    }

    @Operation(summary = "패키지 등록 또는 갱신 (멱등)")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "등록 또는 갱신 성공"),
            @ApiResponse(responseCode = "400", description = "요청 형식 오류")
    })
    @PutMapping("/{id}")
    public PackageResponse upsert(@PathVariable String id,
                                  @Valid @RequestBody UpsertPackageRequest request,
                                  @RequestHeader(value = Headers.CORRELATION_ID, required = false)
                                  String correlationId) {

        PackageId packageId = PackageId.of(id);
        PackageWeight weight = new PackageWeight(request.weightValue(),
                PackageWeight.WeightUnit.valueOf(request.weightUnit()));
        Instant now = clock.instant();

        PackageAggregate aggregate = repository.findById(packageId)
                .map(existing -> {
                    existing.updateWeight(weight, now);
                    existing.updateSize(request.size(), now);
                    return existing;
                })
                .orElseGet(() -> PackageAggregate.register(packageId, weight, request.size(),
                        request.description(), correlationId, now));

        return PackageResponse.from(repository.save(aggregate));
    }

    @Operation(summary = "패키지 조회")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "조회 성공"),
            @ApiResponse(responseCode = "404", description = "패키지 없음")
    })
    @GetMapping("/{id}")
    public PackageResponse get(@PathVariable String id) {
        return PackageResponse.from(repository.findById(PackageId.of(id))
                .orElseThrow(() -> new NoSuchElementException("패키지를 찾을 수 없습니다: " + id)));
    }

    @Operation(summary = "패키지 삭제 (보상 트랜잭션 · 내부)",
            description = "이미 없어도 204 를 반환한다 — 보상은 멱등해야 하기 때문이다.")
    @ApiResponse(responseCode = "204", description = "삭제 완료 또는 대상 없음")
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable String id) {
        repository.deleteById(PackageId.of(id));
        return ResponseEntity.noContent().build();
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ProblemDetail onNotFound(NoSuchElementException e) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
        p.setTitle("패키지를 찾을 수 없습니다");
        p.setType(URI.create(ErrorCodes.PACKAGE_NOT_FOUND));
        return p;
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ProblemDetail onIllegalArgument(IllegalArgumentException e) {
        ProblemDetail p = ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
        p.setTitle("요청이 올바르지 않습니다");
        p.setType(URI.create(ErrorCodes.VALIDATION_FAILED));
        return p;
    }

    // ─────────────────────────────────────────── DTO

    @Schema(description = "패키지 등록·갱신 요청")
    public record UpsertPackageRequest(
            @Schema(example = "2.5") @NotNull @DecimalMin("0.001") BigDecimal weightValue,
            @Schema(example = "KG", allowableValues = {"KG", "G"}) @NotBlank String weightUnit,
            @NotNull PackageSize size,
            @Size(max = 200) String description) {
    }

    @Schema(description = "패키지 정보")
    public record PackageResponse(String packageId, BigDecimal weightKg, String size,
                                  String description, List<String> tags,
                                  boolean deliverableByDrone, Instant updatedAt, long version) {

        public static PackageResponse from(PackageAggregate p) {
            return new PackageResponse(p.id().value(), p.weight().toKilograms(),
                    p.size().name(), p.description(),
                    p.tags().stream().map(PackageAggregate.Tag::code).toList(),
                    p.deliverableByDrone(), p.updatedAt(), p.version());
        }
    }
}
