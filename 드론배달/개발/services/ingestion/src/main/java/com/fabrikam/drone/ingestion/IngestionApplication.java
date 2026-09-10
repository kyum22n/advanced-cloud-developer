package com.fabrikam.drone.ingestion;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** 배달 요청 수신 · 큐 게시 */
@SpringBootApplication
@OpenAPIDefinition(info = @Info(title = "ingestion API", version = "1.0.0",
        description = "배달 요청 수신 · 큐 게시"))
public class IngestionApplication {
    public static void main(String[] args) {
        SpringApplication.run(IngestionApplication.class, args);
    }
}
