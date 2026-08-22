"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { resolveAuthMode, workloadIdentityAvailable, authInfo } = require("../../src/lib/authmode");

const WI = {
  AZURE_CLIENT_ID: "00000000-0000-0000-0000-000000000001",
  AZURE_TENANT_ID: "00000000-0000-0000-0000-000000000002",
  AZURE_FEDERATED_TOKEN_FILE: "/var/run/secrets/azure/tokens/azure-identity-token",
};

// U-A-07 : 워크로드 ID 환경 변수 3종이 모두 있어야 '사용 가능'으로 본다
test("U-A-07 워크로드 ID 감지 — 3종이 모두 있어야 true", () => {
  assert.equal(workloadIdentityAvailable(WI), true);
  assert.equal(workloadIdentityAvailable({ ...WI, AZURE_TENANT_ID: "" }), false);
  assert.equal(workloadIdentityAvailable({}), false);
});

// U-A-08 : 비밀번호가 없고 워크로드 ID 가 있으면 토큰 인증을 고른다
test("U-A-08 인증 방식 자동 선택", () => {
  assert.equal(resolveAuthMode({ ...WI }), "entra");
  assert.equal(resolveAuthMode({ ...WI, DB_PASSWORD: "p" }), "password");
  assert.equal(resolveAuthMode({ DB_PASSWORD: "p" }), "password");
  assert.equal(resolveAuthMode({}), "password");
});

// U-A-09 : 명시 지정이 자동 선택보다 우선한다
test("U-A-09 DB_AUTH_MODE 명시 지정이 우선", () => {
  assert.equal(resolveAuthMode({ ...WI, DB_PASSWORD: "p", DB_AUTH_MODE: "entra" }), "entra");
  assert.equal(resolveAuthMode({ ...WI, DB_AUTH_MODE: "password" }), "password");
  assert.equal(resolveAuthMode({ ...WI, DB_AUTH_MODE: "ENTRA" }), "entra");
  // 알 수 없는 값은 무시하고 자동 선택으로 되돌아간다
  assert.equal(resolveAuthMode({ ...WI, DB_AUTH_MODE: "kerberos" }), "entra");
});

// U-A-10 : 진단 정보에 비밀값이 절대 섞이지 않는다
test("U-A-10 authInfo 는 비밀값을 노출하지 않는다", () => {
  const info = authInfo({ ...WI, DB_PASSWORD: "super-secret", DB_USER: "id-myapp-prd" });
  assert.equal(info.mode, "password");
  assert.equal(info.user, "id-myapp-prd");
  assert.equal(info.passwordConfigured, true);
  const serialized = JSON.stringify(info);
  assert.ok(!serialized.includes("super-secret"), "비밀번호 값이 응답에 포함되면 안 된다");
  assert.ok(!("password" in info));
  assert.ok(!("token" in info));
});
