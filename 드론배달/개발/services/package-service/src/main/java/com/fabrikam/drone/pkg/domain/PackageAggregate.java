package com.fabrikam.drone.pkg.domain;

import com.fabrikam.drone.contract.event.DomainEvent;
import com.fabrikam.drone.contract.event.EventTypes;
import com.fabrikam.drone.contract.vo.PackageSize;
import com.fabrikam.drone.contract.vo.PackageWeight;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * 패키지 — 애그리거트 루트.
 *
 * <p>클래스 이름이 {@code Package} 가 아닌 이유 — Java 의 {@code java.lang.Package} 와 충돌한다.
 * 유비쿼터스 언어는 «패키지»이고, 코드에서는 접미사를 붙인다.
 * <b>언어를 바꾸는 것이 아니라 기술적 제약을 표시</b>하는 것이므로 허용되는 타협이다.
 *
 * <p>배달과 <b>수명 주기가 다르다</b> — 같은 패키지가 반송되어 다시 배달될 수 있다.
 * 그래서 Delivery 안에 넣지 않고 별도 애그리거트로 둔다.
 */
public class PackageAggregate {

    private final PackageId id;
    private PackageWeight weight;
    private PackageSize size;
    private String description;
    private final List<Tag> tags = new ArrayList<>();
    private final Instant createdAt;
    private Instant updatedAt;
    private long version;

    private final transient List<DomainEvent> pendingEvents = new ArrayList<>();

    private PackageAggregate(PackageId id, PackageWeight weight, PackageSize size,
                             String description, Instant createdAt) {
        this.id = id;
        this.weight = weight;
        this.size = size;
        this.description = description;
        this.createdAt = createdAt;
        this.updatedAt = createdAt;
    }

    public static PackageAggregate register(PackageId id, PackageWeight weight, PackageSize size,
                                            String description, String correlationId, Instant now) {
        if (weight == null) {
            throw new IllegalArgumentException("패키지 무게는 필수입니다.");
        }
        if (size == null) {
            throw new IllegalArgumentException("패키지 크기는 필수입니다.");
        }
        PackageAggregate p = new PackageAggregate(id, weight, size, description, now);
        p.pendingEvents.add(DomainEvent.of(EventTypes.PACKAGE_REGISTERED, id.value(),
                correlationId, Map.of(
                        "packageId", id.value(),
                        "weightKg", weight.toKilograms().toPlainString(),
                        "size", size.name())));
        return p;
    }

    public static PackageAggregate restore(PackageId id, PackageWeight weight, PackageSize size,
                                           String description, List<Tag> tags,
                                           Instant createdAt, Instant updatedAt, long version) {
        PackageAggregate p = new PackageAggregate(id, weight, size, description, createdAt);
        if (tags != null) {
            p.tags.addAll(tags);
        }
        p.updatedAt = updatedAt;
        p.version = version;
        return p;
    }

    public void updateSize(PackageSize newSize, Instant now) {
        if (newSize == null) {
            throw new IllegalArgumentException("패키지 크기는 필수입니다.");
        }
        this.size = newSize;
        touch(now);
    }

    public void updateWeight(PackageWeight newWeight, Instant now) {
        if (newWeight == null) {
            throw new IllegalArgumentException("패키지 무게는 필수입니다.");
        }
        this.weight = newWeight;
        touch(now);
    }

    public void addTag(Tag tag, Instant now) {
        if (tags.stream().anyMatch(t -> t.code().equals(tag.code()))) {
            return;                                        // 같은 코드의 태그는 하나만
        }
        tags.add(tag);
        touch(now);
    }

    /** 드론으로 배달 가능한가 — 무게와 크기 <b>둘 다</b> 만족해야 한다. */
    public boolean deliverableByDrone() {
        return weight.fitsInDrone() && size.fitsInDrone();
    }

    private void touch(Instant now) {
        this.updatedAt = now;
        this.version++;
    }

    public PackageId id()            { return id; }
    public PackageWeight weight()    { return weight; }
    public PackageSize size()        { return size; }
    public String description()      { return description; }
    public List<Tag> tags()          { return Collections.unmodifiableList(tags); }
    public Instant createdAt()       { return createdAt; }
    public Instant updatedAt()       { return updatedAt; }
    public long version()            { return version; }

    public List<DomainEvent> drainEvents() {
        List<DomainEvent> out = List.copyOf(pendingEvents);
        pendingEvents.clear();
        return out;
    }

    /** 패키지 식별자. */
    public record PackageId(String value) {
        public PackageId {
            if (value == null || value.isBlank()) {
                throw new IllegalArgumentException("패키지 ID 는 비어 있을 수 없습니다.");
            }
        }

        public static PackageId of(String v) {
            return new PackageId(v);
        }

        @Override
        public String toString() {
            return value;
        }
    }

    /** 태그 — 패키지 애그리거트의 하위 엔터티. */
    public record Tag(String tagId, String code) {
        public Tag {
            if (code == null || code.isBlank()) {
                throw new IllegalArgumentException("태그 코드는 필수입니다.");
            }
        }
    }
}
