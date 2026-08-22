# Backend — Java Spring Boot

| 항목 | 값 |
| --- | --- |
| 런타임 | Java 17 · Spring Boot 3.3 |
| 빌드 | Maven |
| DB 접근 | `spring-boot-starter-jdbc` (JdbcTemplate) |
| 정적 검증 | Checkstyle · SpotBugs |
| 계약 | [`개발/공통/openapi.yaml`](../../공통/openapi.yaml) |

## 실행

```powershell
$env:JAVA_HOME = "C:\dev\build\jdk-17"
mvn spring-boot:run
```

## 정적 검증

```powershell
mvn -B checkstyle:check spotbugs:check
```

## 계층 구조 — 의존 방향은 한쪽으로만

```
web (Controller)  →  service  →  repo  →  DB
        ↓                ↓
      domain (순수 로직 · 외부 의존 없음)
```

- `domain/SummaryCalculator` 와 `config/AuthMode` 는 **외부 의존이 없어 단위 테스트로 고정**합니다.
- 컨트롤러는 얇게 두고 규칙은 `service` 에 모읍니다(설계/공통/02 §P5).
