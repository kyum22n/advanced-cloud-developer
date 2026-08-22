package kr.co.metanet.myapp.config;

import kr.co.metanet.myapp.service.ItemService;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/** 기동 시 스키마를 준비한다. 실패해도 앱은 뜨고 {@code /readyz} 가 503 을 돌려준다. */
@Component
public class SchemaInitializer implements ApplicationRunner {

    private final ItemService service;

    public SchemaInitializer(ItemService service) {
        this.service = service;
    }

    @Override
    public void run(ApplicationArguments args) {
        try {
            service.init();
        } catch (RuntimeException ex) {
            // 기동 자체를 막지 않는다 — 준비 여부는 /readyz 가 판단한다.
            org.slf4j.LoggerFactory.getLogger(SchemaInitializer.class)
                    .warn("스키마 준비 실패 — /readyz 가 503 을 반환합니다: {}", ex.getMessage());
        }
    }
}
