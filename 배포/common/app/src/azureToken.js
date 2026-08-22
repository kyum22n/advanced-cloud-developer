"use strict";
/**
 * 워크로드 ID(Workload Identity) 로 Entra ID 액세스 토큰을 받아 온다.
 *
 * 왜 라이브러리를 쓰지 않는가
 *   - 이 과정의 목적은 «토큰이 어디서 어떻게 나오는가»를 보이는 것입니다.
 *   - 추가 의존성(@azure/identity) 없이 Node 20 의 fetch 만으로 충분합니다.
 *
 * 어떤 값도 앱이 «보관»하지 않습니다
 *   - AKS 워크로드 ID 웹훅이 파드에 아래 네 가지를 주입합니다.
 *       AZURE_CLIENT_ID            : 관리 ID 의 clientId
 *       AZURE_TENANT_ID            : 테넌트
 *       AZURE_FEDERATED_TOKEN_FILE : 짧은 수명의 프로젝티드 SA 토큰 경로
 *       AZURE_AUTHORITY_HOST       : 로그인 엔드포인트
 *   - 앱은 이 SA 토큰을 «증거»로 제출하고 Entra 액세스 토큰과 교환합니다.
 *   - 비밀번호도, 클라이언트 시크릿도 코드·이미지·환경 변수에 없습니다.
 */
const fs = require("fs/promises");

/** PostgreSQL 유연한 서버용 Entra 스코프 */
const SCOPE_POSTGRES = "https://ossrdbms-aad.database.windows.net/.default";

const cache = new Map(); // scope -> { token, expiresAt }

function workloadIdentityAvailable() {
  return Boolean(
    process.env.AZURE_CLIENT_ID &&
      process.env.AZURE_TENANT_ID &&
      process.env.AZURE_FEDERATED_TOKEN_FILE
  );
}

/** JWT 의 exp 를 읽는다(서명 검증은 발급자 몫 — 여기서는 만료 시각만 본다). */
function readExp(jwt) {
  try {
    const payload = JSON.parse(
      Buffer.from(jwt.split(".")[1], "base64url").toString("utf8")
    );
    return typeof payload.exp === "number" ? payload.exp * 1000 : 0;
  } catch {
    return 0;
  }
}

/**
 * 액세스 토큰을 얻는다. 만료 5분 전까지는 캐시를 재사용한다.
 * @param {string} scope 기본값은 PostgreSQL 스코프
 * @returns {Promise<string>}
 */
async function getAccessToken(scope = SCOPE_POSTGRES) {
  const hit = cache.get(scope);
  if (hit && hit.expiresAt - Date.now() > 5 * 60 * 1000) return hit.token;

  if (!workloadIdentityAvailable()) {
    throw new Error(
      "워크로드 ID 환경 변수가 없습니다. AKS 에서 ServiceAccount 주석과 " +
        'Pod 라벨 azure.workload.identity/use="true" 를 확인하세요.'
    );
  }

  const assertion = (
    await fs.readFile(process.env.AZURE_FEDERATED_TOKEN_FILE, "utf8")
  ).trim();

  const authority = (
    process.env.AZURE_AUTHORITY_HOST || "https://login.microsoftonline.com/"
  ).replace(/\/?$/, "/");
  const url = `${authority}${process.env.AZURE_TENANT_ID}/oauth2/v2.0/token`;

  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: process.env.AZURE_CLIENT_ID,
    scope,
    client_assertion_type:
      "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
    client_assertion: assertion,
  });

  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  if (!res.ok) {
    // 토큰 값이나 assertion 은 절대 로그에 남기지 않는다
    throw new Error(`Entra 토큰 교환 실패: HTTP ${res.status}`);
  }
  const json = await res.json();
  const token = json.access_token;
  if (!token) throw new Error("Entra 응답에 access_token 이 없습니다.");

  const exp = readExp(token) || Date.now() + (json.expires_in || 3600) * 1000;
  cache.set(scope, { token, expiresAt: exp });
  return token;
}

module.exports = { getAccessToken, workloadIdentityAvailable, SCOPE_POSTGRES };
