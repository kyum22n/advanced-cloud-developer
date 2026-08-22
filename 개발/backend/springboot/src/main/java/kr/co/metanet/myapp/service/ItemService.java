package kr.co.metanet.myapp.service;

import java.math.BigDecimal;
import java.util.List;
import kr.co.metanet.myapp.domain.Item;
import kr.co.metanet.myapp.domain.SummaryCalculator;
import kr.co.metanet.myapp.domain.WeekSummary;
import kr.co.metanet.myapp.repo.ItemRepository;
import kr.co.metanet.myapp.web.ValidationException;
import org.springframework.stereotype.Service;

/** 항목 유스케이스. 컨트롤러는 얇게 두고 규칙은 여기 모은다. */
@Service
public class ItemService {

    private final ItemRepository repository;

    public ItemService(ItemRepository repository) {
        this.repository = repository;
    }

    /** 기동 시 스키마를 준비한다. */
    public void init() {
        repository.ensureSchema();
    }

    /** DB 준비 여부. */
    public boolean ready() {
        return repository.ping();
    }

    /**
     * 목록을 조회한다.
     *
     * @param limit 최대 건수
     * @return 중복이 제거된 최신순 목록
     */
    public List<Item> list(int limit) {
        return SummaryCalculator.dedupeById(repository.findRecent(limit));
    }

    /**
     * 항목을 등록한다. 검증 실패는 400 으로 매핑된다.
     *
     * @param title  제목
     * @param amount 금액(널 허용)
     * @param actor  감사 로그 행위자
     * @return 저장된 항목
     */
    public Item create(String title, BigDecimal amount, String actor) {
        String trimmed = title == null ? "" : title.trim();
        if (trimmed.isEmpty()) {
            throw new ValidationException("title 은 필수이며 빈 문자열일 수 없습니다.");
        }
        BigDecimal value = amount == null ? BigDecimal.ZERO : amount;
        Item saved = repository.insert(trimmed, value);
        repository.audit(actor == null || actor.isBlank() ? "anonymous" : actor,
                "create", "item:" + saved.id());
        return saved;
    }

    /** 주차별 집계. */
    public List<WeekSummary> summary() {
        return SummaryCalculator.summarizeByWeek(repository.findAll());
    }
}
