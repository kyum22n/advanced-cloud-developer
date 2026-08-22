package kr.co.metanet.myapp.config;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * DB 인증 방식을 «환경이 스스로» 고르게 하는 순수 로직.
 *
 * <p>설계 근거: 설계/공통/07_아이덴티티·시크릿_설계서.md §5.
 * dev·stg 는 비밀번호, prd 는 워크로드 ID 토큰을 쓰지만 <b>이미지는 하나</b>다.</p>
 */
public final class AuthMode {

    /** 비밀번호 기반 인증. */
    public static final String PASSWORD = "password";
    /** Entra ID 토큰 기반 인증. */
    public static final String ENTRA = "entra";

    private AuthMode() {
    }

    /**
     * 워크로드 ID 환경 변수 3종이 모두 있는지 본다.
     *
     * @param env 환경 변수 맵
     * @return 사용 가능 여부
     */
    public static boolean workloadIdentityAvailable(Map<String, String> env) {
        return notBlank(env.get("AZURE_CLIENT_ID"))
                && notBlank(env.get("AZURE_TENANT_ID"))
                && notBlank(env.get("AZURE_FEDERATED_TOKEN_FILE"));
    }

    /**
     * 인증 방식을 결정한다. 명시 지정이 자동 선택보다 우선한다.
     *
     * @param env 환경 변수 맵
     * @return {@link #ENTRA} 또는 {@link #PASSWORD}
     */
    public static String resolve(Map<String, String> env) {
        String explicit = String.valueOf(env.getOrDefault("DB_AUTH_MODE", "")).toLowerCase(java.util.Locale.ROOT);
        if (ENTRA.equals(explicit) || PASSWORD.equals(explicit)) {
            return explicit;
        }
        if (workloadIdentityAvailable(env) && !notBlank(env.get("DB_PASSWORD"))) {
            return ENTRA;
        }
        return PASSWORD;
    }

    /**
     * 진단 정보를 만든다. 자격 증명 «값»은 어떤 경우에도 담지 않는다.
     *
     * @param env 환경 변수 맵
     * @return 인증 방식 요약
     */
    public static Map<String, Object> info(Map<String, String> env) {
        Map<String, Object> info = new LinkedHashMap<>();
        info.put("mode", resolve(env));
        info.put("user", env.getOrDefault("DB_USER", "appuser"));
        info.put("workloadIdentity", workloadIdentityAvailable(env));
        info.put("passwordConfigured", notBlank(env.get("DB_PASSWORD")));
        return info;
    }

    private static boolean notBlank(String value) {
        return value != null && !value.isBlank();
    }
}
