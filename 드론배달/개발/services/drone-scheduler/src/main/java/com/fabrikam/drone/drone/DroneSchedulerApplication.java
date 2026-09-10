package com.fabrikam.drone.drone;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** 드론 애그리거트 · 할당 · 위치 */
@SpringBootApplication
@OpenAPIDefinition(info = @Info(title = "drone-scheduler API", version = "1.0.0",
        description = "드론 애그리거트 · 할당 · 위치"))
public class DroneSchedulerApplication {
    public static void main(String[] args) {
        SpringApplication.run(DroneSchedulerApplication.class, args);
    }
}
