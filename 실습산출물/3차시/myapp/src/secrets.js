"use strict";
/**
 * "환경이 스스로 인증 방식을 고르게" 하는 비밀값 해석기.
 * 배포/common/app/src/lib/authmode.js + src/db.js 의 password/entra 패턴을
 * GitHub PAT·Notion 토큰에 적용한 버전이다.
 *
 *   env      : 일반 환경 변수(k8s Secret)에서 그대로 읽는다  (dev · stg, 그리고 CSI가
 *              Key Vault → k8s Secret 동기화를 이미 마친 prd 도 평소엔 여기 해당)
 *   keyvault : 워크로드 ID로 Entra 토큰을 받아 Key Vault에서 직접 읽는다
 *              (env가 비어 있고 워크로드 ID가 있는 경우 — CSI 동기화가 아직 안 됐거나
 *              실패했을 때의 자가 복구 경로)
 *   unset    : 둘 다 없음 — 앱은 "미설정"으로 정상 동작(기능만 축소)한다
 *
 * 순수 함수(resolveSecretSource)는 네트워크 없이 그대로 단위 테스트할 수 있다.
 */
const { workloadIdentityAvailable, getKeyVaultSecret } = require("./azureIdentity");

function resolveSecretSource(envVarName, env = process.env) {
  if (env[envVarName]) return "env";
  if (workloadIdentityAvailable(env) && env.KEYVAULT_NAME) return "keyvault";
  return "unset";
}

const cache = new Map(); // envVarName -> value (요청마다 다시 fetch하지 않도록 프로세스 내 캐시)

/**
 * @param {string} envVarName 예: 'GITHUB_TOKEN'
 * @param {string} kvSecretName Key Vault 상의 시크릿 이름. 예: 'github-token'
 * @returns {Promise<string>} 값이 없으면 빈 문자열
 */
async function getSecret(envVarName, kvSecretName) {
  const source = resolveSecretSource(envVarName);
  if (source === "env") return process.env[envVarName];
  if (source === "unset") return "";

  if (cache.has(envVarName)) return cache.get(envVarName);
  try {
    const value = await getKeyVaultSecret(process.env.KEYVAULT_NAME, kvSecretName);
    cache.set(envVarName, value || "");
    return value || "";
  } catch (err) {
    // Key Vault 조회 실패도 "미설정"과 동일하게 취급한다 — 앱을 죽이지 않는다.
    console.error(`[secrets] Key Vault에서 ${kvSecretName} 조회 실패:`, err.message);
    return "";
  }
}

/** 진단용 요약 — 실제 값은 절대 담지 않는다(출처만). /version 등에서 그대로 노출해도 안전하다. */
function secretsDiagnostics(env = process.env) {
  const names = [
    ["GITHUB_TOKEN", "github-token"],
    ["NOTION_TOKEN", "notion-token"],
    ["NOTION_PARENT_PAGE_ID", "notion-parent-page-id"],
  ];
  const sources = {};
  for (const [envVarName] of names) sources[envVarName] = resolveSecretSource(envVarName, env);
  return {
    workloadIdentity: workloadIdentityAvailable(env),
    keyVaultConfigured: Boolean(env.KEYVAULT_NAME),
    sources,
  };
}

module.exports = { resolveSecretSource, getSecret, secretsDiagnostics };
