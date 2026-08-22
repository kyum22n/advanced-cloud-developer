"use strict";
// 단위 테스트 — 빌드 산출물(dist)이 아니라 순수 로직을 검증한다.
// TypeScript 원본과 동일한 규칙을 JS 로 옮겨 의존성 없이 실행할 수 있게 한다.
const test = require("node:test");
const assert = require("node:assert/strict");

const WI = {
  AZURE_CLIENT_ID: "cid",
  AZURE_TENANT_ID: "tid",
  AZURE_FEDERATED_TOKEN_FILE: "/var/run/secrets/azure/tokens/azure-identity-token",
};

const notBlank = (v) => typeof v === "string" && v.trim() !== "";
const workloadIdentityAvailable = (env) =>
  notBlank(env.AZURE_CLIENT_ID) && notBlank(env.AZURE_TENANT_ID) && notBlank(env.AZURE_FEDERATED_TOKEN_FILE);
const resolveAuthMode = (env) => {
  const explicit = String(env.DB_AUTH_MODE ?? "").toLowerCase();
  if (explicit === "entra" || explicit === "password") return explicit;
  if (workloadIdentityAvailable(env) && !notBlank(env.DB_PASSWORD)) return "entra";
  return "password";
};

test("U-A-07 워크로드 ID 는 3종이 모두 있어야 사용 가능", () => {
  assert.equal(workloadIdentityAvailable(WI), true);
  assert.equal(workloadIdentityAvailable({ ...WI, AZURE_TENANT_ID: "" }), false);
});

test("U-A-08 인증 방식 자동 선택", () => {
  assert.equal(resolveAuthMode({ ...WI }), "entra");
  assert.equal(resolveAuthMode({ ...WI, DB_PASSWORD: "p" }), "password");
  assert.equal(resolveAuthMode({}), "password");
});

test("U-A-09 명시 지정이 우선", () => {
  assert.equal(resolveAuthMode({ ...WI, DB_PASSWORD: "p", DB_AUTH_MODE: "entra" }), "entra");
  assert.equal(resolveAuthMode({ ...WI, DB_AUTH_MODE: "kerberos" }), "entra");
});
