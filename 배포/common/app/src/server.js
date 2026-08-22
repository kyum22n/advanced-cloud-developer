"use strict";
const http = require("http");
const fs = require("fs");
const path = require("path");
const { createPool, ensureSchema, authInfo } = require("./db");
const { summarizeByWeek, dedupeById } = require("./lib/summary");

const PORT = Number(process.env.PORT || 8080);
const APP_ENV = process.env.APP_ENV || "dev";
const pool = createPool();
let dbReady = false;

async function init() {
  try {
    await ensureSchema(pool);
    dbReady = true;
    console.log(`[startup] schema ready (env=${APP_ENV})`);
  } catch (e) {
    dbReady = false;
    console.error("[startup] db not ready:", e.message);
  }
}

function json(res, code, body) {
  const s = JSON.stringify(body);
  res.writeHead(code, { "Content-Type": "application/json; charset=utf-8", "Content-Length": Buffer.byteLength(s) });
  res.end(s);
}

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  if (!chunks.length) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { return null; }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  try {
    // ── 헬스 프로브 ─────────────────────────────────────────────
    if (url.pathname === "/healthz") return json(res, 200, { status: "ok", env: APP_ENV });
    if (url.pathname === "/readyz") {
      if (!dbReady) { try { await ensureSchema(pool); dbReady = true; } catch { /* keep false */ } }
      return dbReady ? json(res, 200, { status: "ready" }) : json(res, 503, { status: "not-ready" });
    }
    if (url.pathname === "/version") {
      // 인증 '방식'만 노출한다 — 토큰·비밀번호 값은 어떤 경우에도 응답에 넣지 않는다
      return json(res, 200, { version: process.env.APP_VERSION || "0.0.0", env: APP_ENV, auth: authInfo() });
    }

    // ── API ────────────────────────────────────────────────────
    if (url.pathname === "/api/items" && req.method === "GET") {
      const r = await pool.query("SELECT id, title, amount, created_at FROM items ORDER BY id DESC LIMIT 200");
      const items = dedupeById(r.rows.map(x => ({ id: x.id, title: x.title, amount: Number(x.amount), createdAt: x.created_at })));
      return json(res, 200, { count: items.length, items });
    }
    if (url.pathname === "/api/items" && req.method === "POST") {
      const body = await readBody(req);
      if (!body || typeof body.title !== "string" || !body.title.trim()) {
        return json(res, 400, { error: "title 은 필수이며 빈 문자열일 수 없습니다." });
      }
      const amount = Number(body.amount || 0);
      if (Number.isNaN(amount)) return json(res, 400, { error: "amount 는 숫자여야 합니다." });
      const r = await pool.query(
        "INSERT INTO items(title, amount) VALUES($1,$2) RETURNING id, title, amount, created_at",
        [body.title.trim(), amount]
      );
      await pool.query("INSERT INTO audit_log(actor, action, target) VALUES($1,$2,$3)",
        [req.headers["x-user"] || "anonymous", "create", `item:${r.rows[0].id}`]);
      return json(res, 201, r.rows[0]);
    }
    if (url.pathname === "/api/summary" && req.method === "GET") {
      const r = await pool.query("SELECT id, amount, created_at FROM items");
      const rows = r.rows.map(x => ({ id: x.id, amount: Number(x.amount), createdAt: x.created_at }));
      return json(res, 200, { weeks: summarizeByWeek(rows) });
    }

    // ── 정적 파일 ───────────────────────────────────────────────
    const file = url.pathname === "/" ? "index.html" : url.pathname.replace(/^\//, "");
    const p = path.join(__dirname, "..", "public", file);
    if (p.startsWith(path.join(__dirname, "..", "public")) && fs.existsSync(p)) {
      res.writeHead(200, { "Content-Type": file.endsWith(".html") ? "text/html; charset=utf-8" : "text/plain; charset=utf-8" });
      return res.end(fs.readFileSync(p));
    }
    return json(res, 404, { error: "not found" });
  } catch (e) {
    console.error("[error]", e.message);
    return json(res, 500, { error: "internal", detail: e.message });
  }
});

init().finally(() => server.listen(PORT, () => console.log(`[listen] :${PORT} env=${APP_ENV}`)));

module.exports = server;
