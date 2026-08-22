package kr.co.metanet.myapp.web;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import kr.co.metanet.myapp.domain.Item;
import kr.co.metanet.myapp.domain.WeekSummary;
import kr.co.metanet.myapp.service.ItemService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** 항목 API. 계약은 개발/공통/openapi.yaml 을 따른다. */
@RestController
@RequestMapping("/api")
public class ItemController {

    private static final int DEFAULT_LIMIT = 200;

    private final ItemService service;

    public ItemController(ItemService service) {
        this.service = service;
    }

    /**
     * 항목 목록.
     *
     * @param limit 최대 건수
     * @return 200
     */
    @GetMapping("/items")
    public Map<String, Object> list(@RequestParam(defaultValue = "200") int limit) {
        List<Item> items = service.list(limit <= 0 ? DEFAULT_LIMIT : limit);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("count", items.size());
        body.put("items", items.stream().map(ItemController::toMap).toList());
        return body;
    }

    /**
     * 항목 등록.
     *
     * @param payload 요청 본문
     * @param actor   X-User 헤더
     * @return 201
     */
    @PostMapping("/items")
    public ResponseEntity<Map<String, Object>> create(
            @RequestBody(required = false) Map<String, Object> payload,
            @RequestHeader(name = "X-User", required = false) String actor) {
        Map<String, Object> body = payload == null ? Map.of() : payload;
        Object rawTitle = body.get("title");
        Item saved = service.create(rawTitle == null ? null : String.valueOf(rawTitle),
                parseAmount(body.get("amount")), actor);
        return ResponseEntity.status(201).body(toMap(saved));
    }

    /**
     * 주차별 집계.
     *
     * @return 200
     */
    @GetMapping("/summary")
    public Map<String, Object> summary() {
        List<WeekSummary> weeks = service.summary();
        return Map.of("weeks", weeks.stream().map(w -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("week", w.week());
            m.put("count", w.count());
            m.put("amount", w.amount());
            return m;
        }).toList());
    }

    private static BigDecimal parseAmount(Object raw) {
        if (raw == null) {
            return BigDecimal.ZERO;
        }
        try {
            return new BigDecimal(String.valueOf(raw).trim());
        } catch (NumberFormatException ex) {
            throw new ValidationException("amount 는 숫자여야 합니다.");
        }
    }

    private static Map<String, Object> toMap(Item item) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", item.id());
        m.put("title", item.title());
        m.put("amount", item.amount());
        m.put("createdAt", item.createdAt().toString());
        return m;
    }
}
