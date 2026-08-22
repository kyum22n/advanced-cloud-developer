"use strict";
/**
 * 통합 테스트 — 실제 API 엔드포인트 + DB 연동을 검증한다.
 * 대상 URL은 BASE_URL 환경 변수로 주입 (환경마다 다름).
 *   dev: http://localhost:8080 / stg·prd: Ingress FQDN
 */
const test = require("node:test");
const assert = require("node:assert");

const BASE = process.env.BASE_URL || "http://localhost:8080";
const RUN_WRITE = String(process.env.ALLOW_WRITE || "true").toLowerCase() === "true";

async function req(path, init) {
  const r = await fetch(BASE + path, init);
  let body = null;
  try { body = await r.json(); } catch { }
  return { status: r.status, body };
}

test("I-01 /healthz 는 200 을 반환한다", async () => {
  const r = await req("/healthz");
  assert.strictEqual(r.status, 200);
  assert.strictEqual(r.body.status, "ok");
});

test("I-02 /readyz 는 DB 연결이 되어야 200", async () => {
  const r = await req("/readyz");
  assert.strictEqual(r.status, 200, `readyz=${r.status} — DB 연결 설정을 확인하세요`);
});

test("I-03 GET /api/items 는 목록 구조를 반환한다", async () => {
  const r = await req("/api/items");
  assert.strictEqual(r.status, 200);
  assert.ok(Array.isArray(r.body.items));
  assert.strictEqual(typeof r.body.count, "number");
});

test("I-04 POST /api/items 는 제목이 없으면 400", async () => {
  const r = await req("/api/items", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ amount: 10 }),
  });
  assert.strictEqual(r.status, 400);
});

test("I-05 POST → GET 왕복으로 저장이 유지된다", { skip: !RUN_WRITE }, async () => {
  const title = `통합테스트-${Date.now()}`;
  const c = await req("/api/items", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ title, amount: 1234 }),
  });
  assert.strictEqual(c.status, 201);
  const l = await req("/api/items");
  assert.ok(l.body.items.some(x => x.title === title), "방금 만든 항목이 목록에 있어야 한다");
});

test("I-06 /api/summary 는 주차 집계를 반환한다", async () => {
  const r = await req("/api/summary");
  assert.strictEqual(r.status, 200);
  assert.ok(Array.isArray(r.body.weeks));
});

// I-A-10 : /version 이 '인증 방식'은 알려주되 '자격 증명'은 절대 흘리지 않는다
test("I-A-10 /version 의 auth 는 방식만 노출하고 비밀값을 담지 않는다", async () => {
  const res = await fetch(`${BASE}/version`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(body.auth, "auth 필드가 있어야 한다");
  assert.ok(["entra", "password"].includes(body.auth.mode), `알 수 없는 mode: ${body.auth.mode}`);
  assert.equal(typeof body.auth.workloadIdentity, "boolean");
  const raw = JSON.stringify(body).toLowerCase();
  for (const forbidden of ["dbpassword", "access_token", "client_secret", "connectionstring"]) {
    assert.ok(!raw.includes(forbidden), `응답에 ${forbidden} 이 포함되면 안 된다`);
  }
});
