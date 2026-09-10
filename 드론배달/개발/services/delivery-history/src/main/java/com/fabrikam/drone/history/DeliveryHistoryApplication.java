package com.fabrikam.drone.history;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** 이력 적재 · 조회 */
@SpringBootApplication
@OpenAPIDefinition(info = @Info(title = "delivery-history API", version = "1.0.0",
        description = "이력 적재 · 조회"))
public class DeliveryHistoryApplication {
    public static void main(String[] args) {
        SpringApplication.run(DeliveryHistoryApplication.class, args);
    }
}
