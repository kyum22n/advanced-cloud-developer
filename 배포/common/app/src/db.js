"use strict";
const { Pool } = require("pg");
const { getAccessToken } = require("./azureToken");
const { resolveAuthMode, authInfo: buildAuthInfo } = require("./lib/authmode");

/**
 * 연결 정보는 환경 변수로만 받는다 — 코드에 비밀값을 두지 않는다.
 *
 * 인증 방식은 두 가지이며, 환경이 스스로 고르게 한다.
 *   password : DB_PASSWORD 로 접속        (dev · stg — in-cluster PostgreSQL)
 *   entra    : Entra ID 액세스 토큰으로 접속 (prd — 비밀번호가 존재하지 않음)
 *
 * 선택 규칙(DB_AUTH_MODE 미지정 시)
 *   워크로드 ID 환경 변수가 있고 DB_PASSWORD 가 비어 있으면 → entra
 *   그 외 → password
 */
function createPool() {
  const mode = resolveAuthMode(process.env);
  const cfg = {
    host: process.env.DB_HOST || "localhost",
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME || "appdb",
    user: process.env.DB_USER || "appuser",
    max: Number(process.env.DB_POOL_MAX || 5),
    connectionTimeoutMillis: 5000,
  };

  if (mode === "entra") {
    // pg 는 password 로 «함수»를 받을 수 있다 — 연결할 때마다 최신 토큰을 발급받는다.
    // 토큰은 수명이 짧고 자동 갱신되므로, 유출되어도 피해 시간이 제한된다.
    cfg.password = async () => getAccessToken();
    // Azure PostgreSQL 유연한 서버는 TLS 가 필수다.
    cfg.ssl = { rejectUnauthorized: false };
  } else {
    cfg.password = process.env.DB_PASSWORD || "";
    if (String(process.env.DB_SSL || "false").toLowerCase() === "true") {
      cfg.ssl = { rejectUnauthorized: false };
    }
  }

  const pool = new Pool(cfg);
  pool.on("error", (e) => {
    // 오류 메시지에 자격 증명이 섞여 나가지 않도록 메시지만 남긴다
    console.error("[db] pool error:", e.message);
  });
  return pool;
}

async function ensureSchema(pool) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS items (
      id          SERIAL PRIMARY KEY,
      title       TEXT        NOT NULL,
      amount      NUMERIC     NOT NULL DEFAULT 0,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    CREATE TABLE IF NOT EXISTS audit_log (
      id         SERIAL PRIMARY KEY,
      actor      TEXT        NOT NULL,
      action     TEXT        NOT NULL,
      target     TEXT,
      at         TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  `);
}

function authInfo() { return buildAuthInfo(process.env); }

module.exports = { createPool, ensureSchema, authInfo };
