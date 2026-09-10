package com.fabrikam.drone.delivery.domain;

import com.fabrikam.drone.contract.vo.Eta;
import com.fabrikam.drone.contract.vo.Location;

import java.time.Duration;
import java.time.Instant;

/**
 * ETA 계산 — 도메인 서비스.
 *
 * <p>«ETA 를 계산하는 주체»가 배달도 드론도 아니기 때문에 도메인 서비스다.
 *
 * <p>⚠️ 본 과정에서는 <b>거리 ÷ 평균 속도</b> 라는 단순 모델을 쓴다.
 * 실제 시스템에서는 기상·경로·교통·배터리를 반영한 예측 모델이 ETA 분석 컨텍스트에 있고,
 * 이 클래스는 그 컨텍스트를 호출하는 얇은 어댑터가 된다.
 * 지금 단순 모델을 쓰는 것과, <b>모델을 바꿀 자리를 남겨 둔 것</b>이 설계다.
 */
public class EtaCalculator {

    /** 드론 순항 속도 (km/h). */
    private final double cruiseSpeedKmh;

    /** 이착륙·적재에 걸리는 고정 시간. */
    private final Duration fixedOverhead;

    public EtaCalculator(double cruiseSpeedKmh, Duration fixedOverhead) {
        if (cruiseSpeedKmh <= 0) {
            throw new IllegalArgumentException("순항 속도는 0보다 커야 합니다.");
        }
        this.cruiseSpeedKmh = cruiseSpeedKmh;
        this.fixedOverhead = fixedOverhead == null ? Duration.ZERO : fixedOverhead;
    }

    /** 기본값 — 순항 60km/h, 고정 오버헤드 4분. */
    public static EtaCalculator standard() {
        return new EtaCalculator(60.0, Duration.ofMinutes(4));
    }

    /**
     * 현재 위치에서 목적지까지의 ETA 를 산출한다.
     *
     * @param confidence 신뢰도 — 위치 정보가 오래됐을수록 낮게 준다
     */
    public Eta estimate(Location from, Location to, Instant now, double confidence) {
        double km = from.distanceKmTo(to);
        long travelSeconds = Math.round(km / cruiseSpeedKmh * 3600.0);
        Instant arrival = now.plus(fixedOverhead).plusSeconds(Math.max(travelSeconds, 1));
        return new Eta(arrival, now, confidence);
    }

    /**
     * 위치 정보의 신선도로 신뢰도를 낮춘다.
     *
     * <p>5분 지난 위치로 계산한 ETA 를 «신뢰도 1.0» 이라고 말하면 거짓말이다.
     */
    public double confidenceFor(Instant locationReportedAt, Instant now) {
        long ageSeconds = Duration.between(locationReportedAt, now).getSeconds();
        if (ageSeconds <= 30)  return 0.95;
        if (ageSeconds <= 120) return 0.80;
        if (ageSeconds <= 300) return 0.60;
        return 0.40;
    }
}
