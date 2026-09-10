package com.fabrikam.drone.contract.vo;

/** 패키지 크기 — 값 개체(열거). 드론 적재함 규격에 대응한다. */
public enum PackageSize {
    SMALL("소형 · 30cm 이하"),
    MEDIUM("중형 · 60cm 이하"),
    LARGE("대형 · 60cm 초과");

    private final String description;

    PackageSize(String description) {
        this.description = description;
    }

    public String description() {
        return description;
    }

    /** 대형은 드론 적재함에 들어가지 않는다. */
    public boolean fitsInDrone() {
        return this != LARGE;
    }
}
