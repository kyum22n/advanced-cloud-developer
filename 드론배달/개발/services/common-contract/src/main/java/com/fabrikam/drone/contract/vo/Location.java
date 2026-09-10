package com.fabrikam.drone.contract.vo;

/**
 * 위치 — 값 개체.
 *
 * <p>좌표가 같으면 같은 위치다. 식별자가 없고 불변이다.
 * {@code record} 로 선언해 equals/hashCode/불변성을 컴파일러가 보장한다.
 *
 * @param latitude  위도 (-90 ~ 90)
 * @param longitude 경도 (-180 ~ 180)
 * @param altitude  고도(m). 지상은 0
 */
public record Location(double latitude, double longitude, double altitude) {

    private static final double EARTH_RADIUS_KM = 6371.0;

    public Location {
        if (latitude < -90 || latitude > 90) {
            throw new IllegalArgumentException("위도는 -90 ~ 90 이어야 합니다: " + latitude);
        }
        if (longitude < -180 || longitude > 180) {
            throw new IllegalArgumentException("경도는 -180 ~ 180 이어야 합니다: " + longitude);
        }
        if (altitude < 0) {
            throw new IllegalArgumentException("고도는 0 이상이어야 합니다: " + altitude);
        }
    }

    public static Location ofGround(double latitude, double longitude) {
        return new Location(latitude, longitude, 0);
    }

    /** 대권 거리(km). ETA 계산의 기초. */
    public double distanceKmTo(Location other) {
        double dLat = Math.toRadians(other.latitude - this.latitude);
        double dLon = Math.toRadians(other.longitude - this.longitude);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                 + Math.cos(Math.toRadians(this.latitude)) * Math.cos(Math.toRadians(other.latitude))
                 * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
