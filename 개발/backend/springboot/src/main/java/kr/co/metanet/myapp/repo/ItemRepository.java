package kr.co.metanet.myapp.repo;

import java.math.BigDecimal;
import java.sql.Timestamp;
import java.util.List;
import kr.co.metanet.myapp.domain.Item;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

/** 항목 저장소. 스키마는 설계/공통/05_데이터모델설계서.md 를 따른다. */
@Repository
public class ItemRepository {

    private static final int MAX_ROWS = 200;

    private static final RowMapper<Item> MAPPER = (rs, rowNum) -> new Item(
            rs.getLong("id"),
            rs.getString("title"),
            rs.getBigDecimal("amount"),
            rs.getTimestamp("created_at").toInstant());

    private final JdbcTemplate jdbc;

    public ItemRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** 앱 기동 시 스키마를 보장한다(실습 범위. 운영은 마이그레이션 도구 권장). */
    public void ensureSchema() {
        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS items (
                  id          SERIAL PRIMARY KEY,
                  title       TEXT        NOT NULL,
                  amount      NUMERIC     NOT NULL DEFAULT 0,
                  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
                )""");
        jdbc.execute("""
                CREATE TABLE IF NOT EXISTS audit_log (
                  id         SERIAL PRIMARY KEY,
                  actor      TEXT        NOT NULL,
                  action     TEXT        NOT NULL,
                  target     TEXT,
                  at         TIMESTAMPTZ NOT NULL DEFAULT now()
                )""");
    }

    /** DB 가 응답하는지 확인한다. {@code /readyz} 가 이 결과에 의존한다. */
    public boolean ping() {
        Integer one = jdbc.queryForObject("SELECT 1", Integer.class);
        return one != null && one == 1;
    }

    /**
     * 최신순으로 항목을 조회한다.
     *
     * @param limit 최대 건수(상한 200)
     * @return 항목 목록
     */
    public List<Item> findRecent(int limit) {
        int bounded = Math.min(Math.max(limit, 1), MAX_ROWS);
        return jdbc.query("SELECT id, title, amount, created_at FROM items ORDER BY id DESC LIMIT ?",
                MAPPER, bounded);
    }

    /** 전체 항목을 조회한다(집계용). */
    public List<Item> findAll() {
        return jdbc.query("SELECT id, title, amount, created_at FROM items ORDER BY id ASC", MAPPER);
    }

    /**
     * 항목을 저장하고 저장된 값을 돌려준다.
     *
     * @param title  제목
     * @param amount 금액
     * @return 저장된 항목
     */
    public Item insert(String title, BigDecimal amount) {
        return jdbc.queryForObject(
                "INSERT INTO items (title, amount) VALUES (?, ?) RETURNING id, title, amount, created_at",
                MAPPER, title, amount);
    }

    /**
     * 감사 로그를 남긴다.
     *
     * @param actor  행위자
     * @param action 행위
     * @param target 대상
     */
    public void audit(String actor, String action, String target) {
        jdbc.update("INSERT INTO audit_log (actor, action, target, at) VALUES (?, ?, ?, ?)",
                actor, action, target, Timestamp.from(java.time.Instant.now()));
    }
}
