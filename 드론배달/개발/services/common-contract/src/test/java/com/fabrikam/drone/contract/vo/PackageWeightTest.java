package com.fabrikam.drone.contract.vo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("PackageWeight 값 개체")
class PackageWeightTest {

    @Test
    @DisplayName("무게는 0보다 커야 한다")
    void rejectsNonPositive() {
        assertThrows(IllegalArgumentException.class, () -> PackageWeight.ofKilograms("0"));
        assertThrows(IllegalArgumentException.class, () -> PackageWeight.ofKilograms("-1"));
    }

    @Test
    @DisplayName("g 을 kg 으로 변환한다 — 단위 착각 방지")
    void convertsGramsToKilograms() {
        PackageWeight w = new PackageWeight(new BigDecimal("2500"), PackageWeight.WeightUnit.G);
        assertEquals(0, w.toKilograms().compareTo(new BigDecimal("2.500")));
    }

    @Test
    @DisplayName("5kg 이하는 드론에 적재 가능하다")
    void fitsInDrone() {
        assertTrue(PackageWeight.ofKilograms("2.5").fitsInDrone());
        assertTrue(PackageWeight.ofKilograms("5.0").fitsInDrone());
        assertFalse(PackageWeight.ofKilograms("5.001").fitsInDrone());
    }

    @Test
    @DisplayName("5000g 은 5kg 과 같이 취급된다")
    void unitConsistency() {
        PackageWeight g = new PackageWeight(new BigDecimal("5000"), PackageWeight.WeightUnit.G);
        assertTrue(g.fitsInDrone());
    }
}
