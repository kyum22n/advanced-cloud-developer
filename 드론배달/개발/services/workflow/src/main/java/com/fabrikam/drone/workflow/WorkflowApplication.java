package com.fabrikam.drone.workflow;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/** 큐 소비 · Saga 조정 · 감시 */
@SpringBootApplication
@OpenAPIDefinition(info = @Info(title = "workflow API", version = "1.0.0",
        description = "큐 소비 · Saga 조정 · 감시"))
public class WorkflowApplication {
    public static void main(String[] args) {
        SpringApplication.run(WorkflowApplication.class, args);
    }
}
