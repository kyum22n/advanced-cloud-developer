"use strict";
/**
 * DB 인증 방식을 «환경이 스스로» 고르게 하는 순수 함수.
 * 외부 의존이 없으므로 단위 테스트에서 그대로 검증한다.
 *
 *   password : DB_PASSWORD 로 접속        (dev · stg)
 *   entra    : Entra ID 액세스 토큰으로 접속 (prd — 비밀번호가 존재하지 않음)
 */
function workloadIdentityAvailable(env) {
  return Boolean(
    env.AZURE_CLIENT_ID && env.AZURE_TENANT_ID && env.AZURE_FEDERATED_TOKEN_FILE
  );
}

function resolveAuthMode(env) {
  const explicit = String(env.DB_AUTH_MODE || "").toLowerCase();
  if (explicit === "entra" || explicit === "password") return explicit;
  if (workloadIdentityAvailable(env) && !env.DB_PASSWORD) return "entra";
  return "password";
}

/** 진단용 요약 — 비밀값은 절대 담지 않는다(존재 여부만). */
function authInfo(env) {
  return {
    mode: resolveAuthMode(env),
    user: env.DB_USER || "appuser",
    workloadIdentity: workloadIdentityAvailable(env),
    passwordConfigured: Boolean(env.DB_PASSWORD),
  };
}

module.exports = { resolveAuthMode, workloadIdentityAvailable, authInfo };
