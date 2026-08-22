/**
 * DB 인증 방식을 «환경이 스스로» 고르게 하는 순수 함수.
 * 설계 근거: 설계/공통/07_아이덴티티·시크릿_설계서.md §5
 *
 * 외부 의존이 없으므로 단위 테스트로 고정한다(U-A-07~10).
 */
export type AuthModeName = 'entra' | 'password';

export interface AuthInfo {
  mode: AuthModeName;
  user: string;
  workloadIdentity: boolean;
  passwordConfigured: boolean;
}

type Env = Record<string, string | undefined>;

const notBlank = (v: string | undefined): boolean => typeof v === 'string' && v.trim() !== '';

/** 워크로드 ID 환경 변수 3종이 모두 있어야 사용 가능으로 본다. */
export function workloadIdentityAvailable(env: Env): boolean {
  return notBlank(env.AZURE_CLIENT_ID) && notBlank(env.AZURE_TENANT_ID) && notBlank(env.AZURE_FEDERATED_TOKEN_FILE);
}

/** 명시 지정이 자동 선택보다 우선한다. 알 수 없는 값은 자동 선택으로 되돌아간다. */
export function resolveAuthMode(env: Env): AuthModeName {
  const explicit = String(env.DB_AUTH_MODE ?? '').toLowerCase();
  if (explicit === 'entra' || explicit === 'password') {
    return explicit;
  }
  if (workloadIdentityAvailable(env) && !notBlank(env.DB_PASSWORD)) {
    return 'entra';
  }
  return 'password';
}

/** 진단용 요약 — 자격 증명 «값»은 어떤 경우에도 담지 않는다(존재 여부만). */
export function authInfo(env: Env): AuthInfo {
  return {
    mode: resolveAuthMode(env),
    user: env.DB_USER ?? 'appuser',
    workloadIdentity: workloadIdentityAvailable(env),
    passwordConfigured: notBlank(env.DB_PASSWORD),
  };
}
