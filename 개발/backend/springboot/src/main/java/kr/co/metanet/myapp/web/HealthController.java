package kr.co.metanet.myapp.web;

import java.util.LinkedHashMap;
import java.util.Map;
import kr.co.metanet.myapp.config.AuthMode;
import kr.co.metanet.myapp.service.ItemService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/** 프로브·버전 엔드포인트. */
@RestController
public class HealthController {

    private final ItemService service;

    public HealthController(ItemService service) {
        this.service = service;
    }

    /**
     * 생존 프로브. <b>의존성을 확인하지 않는다</b> — 여기서 DB 를 보면
     * DB 가 잠시 끊겼을 때 파드가 재시작되어 상황이 악화된다.
     *
     * @return 200
     */
    @GetMapping("/healthz")
    public Map<String, String> healthz() {
        return Map.of("status", "ok", "env", env());
    }

    /**
     * 준비 프로브. DB 연결을 실제로 확인한다.
     *
     * @return 200 또는 503
     */
    @GetMapping("/readyz")
    public ResponseEntity<Map<String, String>> readyz() {
        try {
            if (service.ready()) {
                return ResponseEntity.ok(Map.of("status", "ready"));
            }
        } catch (RuntimeException ex) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(Map.of("status", "not-ready", "reason", "database"));
        }
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(Map.of("status", "not-ready", "reason", "database"));
    }

    /**
     * 배포 버전·환경·인증 방식. 자격 증명 값은 담지 않는다.
     *
     * @return 200
     */
    @GetMapping("/version")
    public Map<String, Object> version() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("version", System.getenv().getOrDefault("APP_VERSION", "0.0.0"));
        body.put("env", env());
        body.put("auth", AuthMode.info(System.getenv()));
        return body;
    }

    private String env() {
        return System.getenv().getOrDefault("APP_ENV", "dev");
    }
}
