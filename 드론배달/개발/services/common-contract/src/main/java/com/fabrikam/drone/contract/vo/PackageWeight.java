package com.fabrikam.drone.contract.vo;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * 패키지 무게 — 값 개체.
 *
 * <p>«2.5» 라는 숫자만 떠다니면 kg 인지 g 인지 알 수 없다.
 * 단위를 값에 묶어 두면 «kg 을 g 으로 착각»하는 부류의 버그가 컴파일 단계에서 사라진다.
 */
public record PackageWeight(BigDecimal value, WeightUnit unit) {

    /** 드론 1대가 운반 가능한 최대 무게. */
    public static final BigDecimal MAX_DRONE_CAPACITY_KG = new BigDecimal("5.000");

    public PackageWeight {
        if (value == null || unit == null) {
            throw new IllegalArgumentException("무게 값과 단위는 필수입니다.");
        }
        if (value.signum() <= 0) {
            throw new IllegalArgumentException("무게는 0보다 커야 합니다: " + value);
        }
    }

    public static PackageWeight ofKilograms(String value) {
        return new PackageWeight(new BigDecimal(value), WeightUnit.KG);
    }

    public BigDecimal toKilograms() {
        return switch (unit) {
            case KG -> value.setScale(3, RoundingMode.HALF_UP);
            case G  -> value.divide(new BigDecimal("1000"), 3, RoundingMode.HALF_UP);
        };
    }

    /** 드론 운반 가능 여부. 초과하면 타사 위탁 대상이 된다. */
    public boolean fitsInDrone() {
        return toKilograms().compareTo(MAX_DRONE_CAPACITY_KG) <= 0;
    }

    public enum WeightUnit { KG, G }
}
