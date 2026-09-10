package com.fabrikam.drone.delivery;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 아키텍처 규칙 테스트.
 *
 * <p>«도메인 계층은 프레임워크를 몰라야 한다»는 규칙은 문서에만 적어 두면 반드시 깨진다.
 * 테스트로 강제하면 규칙을 어긴 순간 빌드가 실패한다.
 */
@DisplayName("아키텍처 규칙")
class ArchitectureRuleTest {

    private static final Path DOMAIN =
            Path.of("src", "main", "java", "com", "fabrikam", "drone", "delivery", "domain");

    /** 도메인 계층에 나타나면 안 되는 import. */
    private static final List<String> FORBIDDEN = List.of(
            "import org.springframework",
            "import jakarta.persistence",
            "import com.azure.",
            "import io.swagger",
            "import com.fasterxml.jackson");

    @Test
    @DisplayName("도메인 계층은 프레임워크에 의존하지 않는다")
    void domainHasNoFrameworkDependency() throws IOException {
        if (!Files.isDirectory(DOMAIN)) {
            return;                                  // 다른 작업 디렉터리에서 실행된 경우 건너뛴다
        }
        List<String> violations = new ArrayList<>();
        try (Stream<Path> files = Files.walk(DOMAIN)) {
            for (Path f : files.filter(p -> p.toString().endsWith(".java")).toList()) {
                String src = Files.readString(f, StandardCharsets.UTF_8);
                for (String forbidden : FORBIDDEN) {
                    if (src.contains(forbidden)) {
                        violations.add(f.getFileName() + " → " + forbidden);
                    }
                }
            }
        }
        assertTrue(violations.isEmpty(),
                "도메인 계층에 프레임워크 의존이 있습니다:\n  " + String.join("\n  ", violations));
    }
}
