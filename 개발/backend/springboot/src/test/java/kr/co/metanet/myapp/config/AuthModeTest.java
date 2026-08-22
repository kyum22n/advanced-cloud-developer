package kr.co.metanet.myapp.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/** 단위 테스트 — 설계/공통/06 의 U-A-07~10 에 대응한다. */
class AuthModeTest {

    private static Map<String, String> wi() {
        Map<String, String> env = new HashMap<>();
        env.put("AZURE_CLIENT_ID", "cid");
        env.put("AZURE_TENANT_ID", "tid");
        env.put("AZURE_FEDERATED_TOKEN_FILE", "/var/run/secrets/azure/tokens/azure-identity-token");
        return env;
    }

    @Test
    @DisplayName("U-A-07 워크로드 ID 는 3종이 모두 있어야 사용 가능")
    void detect() {
        assertTrue(AuthMode.workloadIdentityAvailable(wi()));
        Map<String, String> partial = wi();
        partial.remove("AZURE_TENANT_ID");
        assertFalse(AuthMode.workloadIdentityAvailable(partial));
        assertFalse(AuthMode.workloadIdentityAvailable(Map.of()));
    }

    @Test
    @DisplayName("U-A-08 비밀번호가 없고 워크로드 ID 가 있으면 토큰 인증")
    void autoSelect() {
        assertEquals(AuthMode.ENTRA, AuthMode.resolve(wi()));
        Map<String, String> withPw = wi();
        withPw.put("DB_PASSWORD", "p");
        assertEquals(AuthMode.PASSWORD, AuthMode.resolve(withPw));
        assertEquals(AuthMode.PASSWORD, AuthMode.resolve(Map.of()));
    }

    @Test
    @DisplayName("U-A-09 명시 지정이 자동 선택보다 우선")
    void explicitWins() {
        Map<String, String> env = wi();
        env.put("DB_PASSWORD", "p");
        env.put("DB_AUTH_MODE", "ENTRA");
        assertEquals(AuthMode.ENTRA, AuthMode.resolve(env));
        env.put("DB_AUTH_MODE", "kerberos");
        assertEquals(AuthMode.PASSWORD, AuthMode.resolve(env));
    }

    @Test
    @DisplayName("U-A-10 진단 정보에 비밀값이 담기지 않는다")
    void noSecretLeak() {
        Map<String, String> env = wi();
        env.put("DB_PASSWORD", "super-secret");
        env.put("DB_USER", "id-myapp-prd");
        Map<String, Object> info = AuthMode.info(env);
        assertEquals(AuthMode.PASSWORD, info.get("mode"));
        assertEquals(Boolean.TRUE, info.get("passwordConfigured"));
        assertFalse(info.toString().contains("super-secret"));
        assertFalse(info.containsKey("password"));
    }
}
