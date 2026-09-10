package com.fabrikam.drone.pkg.domain;

import com.fabrikam.drone.contract.event.EventTypes;
import com.fabrikam.drone.contract.vo.PackageSize;
import com.fabrikam.drone.contract.vo.PackageWeight;
import com.fabrikam.drone.pkg.domain.PackageAggregate.PackageId;
import com.fabrikam.drone.pkg.domain.PackageAggregate.Tag;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("PackageAggregate — 패키지 애그리거트")
class PackageAggregateTest {

    private static final Instant NOW = Instant.parse("2026-08-29T10:00:00Z");
    private static final String CORR = "req-test";

    private PackageAggregate register(String weightKg, PackageSize size) {
        return PackageAggregate.register(PackageId.of("pkg-0001"),
                PackageWeight.ofKilograms(weightKg), size, "서류 봉투", CORR, NOW);
    }

    @Test
    @DisplayName("무게가 없으면 등록되지 않는다")
    void requiresWeight() {
        assertThrows(IllegalArgumentException.class,
                () -> PackageAggregate.register(PackageId.of("pkg-0001"), null,
                        PackageSize.SMALL, "설명", CORR, NOW));
    }

    @Test
    @DisplayName("크기가 없으면 등록되지 않는다")
    void requiresSize() {
        assertThrows(IllegalArgumentException.class,
                () -> PackageAggregate.register(PackageId.of("pkg-0001"),
                        PackageWeight.ofKilograms("1.0"), null, "설명", CORR, NOW));
    }

    @Test
    @DisplayName("등록 시 PackageRegistered 이벤트가 발생한다")
    void raisesRegisteredEvent() {
        var events = register("2.5", PackageSize.SMALL).drainEvents();
        assertEquals(1, events.size());
        assertEquals(EventTypes.PACKAGE_REGISTERED, events.get(0).eventType());
        assertEquals("2.500", events.get(0).data().get("weightKg"));
    }

    @Test
    @DisplayName("무게와 크기가 모두 맞아야 드론으로 배달할 수 있다")
    void deliverableRequiresBothWeightAndSize() {
        assertTrue(register("2.5", PackageSize.SMALL).deliverableByDrone());
        assertTrue(register("5.0", PackageSize.MEDIUM).deliverableByDrone());

        assertFalse(register("6.0", PackageSize.SMALL).deliverableByDrone(),
                "무게 초과 — 드론 불가");
        assertFalse(register("1.0", PackageSize.LARGE).deliverableByDrone(),
                "크기 초과 — 드론 불가");
        assertFalse(register("6.0", PackageSize.LARGE).deliverableByDrone());
    }

    @Test
    @DisplayName("같은 코드의 태그는 중복 추가되지 않는다")
    void tagsAreUniqueByCode() {
        PackageAggregate p = register("2.5", PackageSize.SMALL);
        p.addTag(new Tag("tag-1", "FRAGILE"), NOW);
        p.addTag(new Tag("tag-2", "FRAGILE"), NOW.plusSeconds(1));

        assertEquals(1, p.tags().size());
    }

    @Test
    @DisplayName("태그 목록은 밖에서 바꿀 수 없다 — 애그리거트가 자기 내부를 지킨다")
    void tagsAreImmutableFromOutside() {
        PackageAggregate p = register("2.5", PackageSize.SMALL);
        assertThrows(UnsupportedOperationException.class,
                () -> p.tags().add(new Tag("tag-x", "HACK")));
    }

    @Test
    @DisplayName("갱신하면 버전이 올라간다")
    void versionIncrementsOnUpdate() {
        PackageAggregate p = register("2.5", PackageSize.SMALL);
        long v0 = p.version();
        p.updateSize(PackageSize.MEDIUM, NOW.plusSeconds(10));
        assertTrue(p.version() > v0);
    }

    @Test
    @DisplayName("null 로 갱신하려 하면 거부된다")
    void rejectsNullOnUpdate() {
        PackageAggregate p = register("2.5", PackageSize.SMALL);
        assertThrows(IllegalArgumentException.class, () -> p.updateSize(null, NOW));
        assertThrows(IllegalArgumentException.class, () -> p.updateWeight(null, NOW));
    }
}
