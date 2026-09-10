package com.fabrikam.drone.pkg;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** 패키지 애그리거트 */
@SpringBootApplication
@OpenAPIDefinition(info = @Info(title = "package-service API", version = "1.0.0",
        description = "패키지 애그리거트"))
public class PackageApplication {
    public static void main(String[] args) {
        SpringApplication.run(PackageApplication.class, args);
    }
}
