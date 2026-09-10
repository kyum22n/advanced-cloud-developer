package com.fabrikam.drone.drone.infrastructure;

import com.azure.spring.data.cosmos.core.mapping.Container;
import com.azure.spring.data.cosmos.core.mapping.PartitionKey;
import com.fabrikam.drone.contract.vo.DroneStatus;
import com.fabrikam.drone.contract.vo.Location;
import com.fabrikam.drone.drone.domain.Drone;
import com.fabrikam.drone.drone.domain.DroneId;
import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;

import java.math.BigDecimal;
import java.time.Instant;

/**
 * Cosmos DB 문서 표현.
 *
 * <p>파티션 키를 {@code droneId} 로 둔다 — 모든 접근이 ID 기준이므로
 * 단일 파티션 조회가 되어 RU 소비가 최소가 된다.
 *
 * <p>{@code @Version} 이 붙은 {@code _etag} 가 <b>INV-03 의 최종 방어선</b>이다.
 * 두 인스턴스가 같은 드론을 동시에 읽어 할당하려 하면, 나중에 저장하는 쪽이 실패한다.
 */
@Container(containerName = "drones")
public class DroneDocument {

    @Id
    private String id;

    @PartitionKey
    private String droneId;

    private BigDecimal capacityKg;
    private DroneStatus status;
    private Double latitude;
    private Double longitude;
    private Double altitude;
    private Integer batteryPercent;
    private String currentDeliveryId;
    private Instant locationReportedAt;
    private Instant updatedAt;

    /** ★ 낙관적 동시성 — Cosmos DB 가 조건부 쓰기에 사용한다. */
    @Version
    private String etag;

    public DroneDocument() {
    }

    public static DroneDocument from(Drone d) {
        DroneDocument doc = new DroneDocument();
        doc.id = d.id().value();
        doc.droneId = d.id().value();
        doc.capacityKg = d.capacityKg();
        doc.status = d.status();
        Location l = d.currentLocation();
        doc.latitude = l == null ? null : l.latitude();
        doc.longitude = l == null ? null : l.longitude();
        doc.altitude = l == null ? null : l.altitude();
        doc.batteryPercent = d.batteryPercent();
        doc.currentDeliveryId = d.currentDeliveryId().orElse(null);
        doc.locationReportedAt = d.locationReportedAt();
        doc.updatedAt = d.updatedAt();
        doc.etag = d.etag();
        return doc;
    }

    public Drone toDomain() {
        Location loc = (latitude == null || longitude == null) ? null
                : new Location(latitude, longitude, altitude == null ? 0 : altitude);
        return Drone.restore(DroneId.of(droneId), capacityKg, status, loc,
                batteryPercent == null ? 0 : batteryPercent, currentDeliveryId,
                locationReportedAt, updatedAt, etag);
    }

    public String getId()                    { return id; }
    public void setId(String v)              { this.id = v; }
    public String getDroneId()               { return droneId; }
    public void setDroneId(String v)         { this.droneId = v; }
    public BigDecimal getCapacityKg()        { return capacityKg; }
    public void setCapacityKg(BigDecimal v)  { this.capacityKg = v; }
    public DroneStatus getStatus()           { return status; }
    public void setStatus(DroneStatus v)     { this.status = v; }
    public Double getLatitude()              { return latitude; }
    public void setLatitude(Double v)        { this.latitude = v; }
    public Double getLongitude()             { return longitude; }
    public void setLongitude(Double v)       { this.longitude = v; }
    public Double getAltitude()              { return altitude; }
    public void setAltitude(Double v)        { this.altitude = v; }
    public Integer getBatteryPercent()       { return batteryPercent; }
    public void setBatteryPercent(Integer v) { this.batteryPercent = v; }
    public String getCurrentDeliveryId()     { return currentDeliveryId; }
    public void setCurrentDeliveryId(String v) { this.currentDeliveryId = v; }
    public Instant getLocationReportedAt()   { return locationReportedAt; }
    public void setLocationReportedAt(Instant v) { this.locationReportedAt = v; }
    public Instant getUpdatedAt()            { return updatedAt; }
    public void setUpdatedAt(Instant v)      { this.updatedAt = v; }
    public String getEtag()                  { return etag; }
    public void setEtag(String v)            { this.etag = v; }
}
