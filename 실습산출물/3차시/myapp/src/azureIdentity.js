"use strict";
/**
 * 워크로드 ID(Workload Identity)로 Entra ID 액세스 토큰을 받아 온다.
 * 배포/common/app/src/azureToken.js 와 동일한 패턴 — Key Vault 스코프로만 다르다.
 *
 * 어떤 값도 앱이 "보관"하지 않는다 — AKS 워크로드 ID 웹훅이 파드에 아래 네 가지를 주입하고,
 * 앱은 이 짧은 수명의 SA 토큰을 "증거"로 제출해 Entra 액세스 토큰과 교환할 뿐이다.
 *   AZURE_CLIENT_ID / AZURE_TENANT_ID / AZURE_FEDERATED_TOKEN_FILE / AZURE_AUTHORITY_HOST
 */
const fs = require("fs/promises");

const SCOPE_KEYVAULT = "https://vault.azure.net/.default";

const cache = new Map(); // scope -> { token, expiresAt }

function workloadIdentityAvailable(env = process.env) {
  return Boolean(env.AZURE_CLIENT_ID && env.AZURE_TENANT_ID && env.AZURE_FEDERATED_TOKEN_FILE);
}

function readExp(jwt) {
  try {
    const payload = JSON.parse(Buffer.from(jwt.split(".")[1], "base64url").toString("utf8"));
    return typeof payload.exp === "number" ? payload.exp * 1000 : 0;
  } catch {
    return 0;
  }
}

async function getAccessToken(scope = SCOPE_KEYVAULT) {
  const hit = cache.get(scope);
  if (hit && hit.expiresAt - Date.now() > 5 * 60 * 1000) return hit.token;

  if (!workloadIdentityAvailable()) {
    throw new Error("워크로드 ID 환경 변수가 없습니다(AZURE_CLIENT_ID 등). 로컬/dev/stg에서는 정상입니다.");
  }

  const assertion = (await fs.readFile(process.env.AZURE_FEDERATED_TOKEN_FILE, "utf8")).trim();
  const authority = (process.env.AZURE_AUTHORITY_HOST || "https://login.microsoftonline.com/").replace(/\/?$/, "/");
  const url = `${authority}${process.env.AZURE_TENANT_ID}/oauth2/v2.0/token`;

  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: process.env.AZURE_CLIENT_ID,
    scope,
    client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    client_assertion: assertion,
  });

  const res = await fetch(url, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body });
  if (!res.ok) {
    // 토큰 값이나 assertion은 절대 로그에 남기지 않는다
    throw new Error(`Entra 토큰 교환 실패: HTTP ${res.status}`);
  }
  const json = await res.json();
  const token = json.access_token;
  if (!token) throw new Error("Entra 응답에 access_token이 없습니다.");

  const exp = readExp(token) || Date.now() + (json.expires_in || 3600) * 1000;
  cache.set(scope, { token, expiresAt: exp });
  return token;
}

/** Key Vault REST API로 시크릿 하나를 가져온다. 값은 호출자에게만 반환되고 어디에도 기록하지 않는다. */
async function getKeyVaultSecret(vaultName, secretName) {
  const token = await getAccessToken(SCOPE_KEYVAULT);
  const url = `https://${vaultName}.vault.azure.net/secrets/${encodeURIComponent(secretName)}?api-version=7.4`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`Key Vault 조회 실패(${secretName}): HTTP ${res.status}`);
  const json = await res.json();
  return json.value;
}

module.exports = { getAccessToken, getKeyVaultSecret, workloadIdentityAvailable, SCOPE_KEYVAULT };
