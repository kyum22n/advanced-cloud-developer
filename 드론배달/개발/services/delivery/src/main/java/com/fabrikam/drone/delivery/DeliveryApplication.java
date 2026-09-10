package com.fabrikam.drone.delivery;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** 배달 애그리거트 · 상태 · ETA */
@SpringBootApplication
@OpenAPIDefinition(info = @Info(title = "delivery API", version = "1.0.0",
        description = "배달 애그리거트 · 상태 · ETA"))
public class DeliveryApplication {
    public static void main(String[] args) {
        SpringApplication.run(DeliveryApplication.class, args);
    }
}
