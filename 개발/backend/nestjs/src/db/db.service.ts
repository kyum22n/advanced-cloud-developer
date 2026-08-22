import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { Pool, PoolClient } from 'pg';
import { resolveAuthMode } from '../common/authmode';

/**
 * 연결 정보는 환경 변수로만 받는다 — 코드·이미지에 비밀을 두지 않는다.
 *
 * prd 에서는 워크로드 ID 토큰으로 접속하므로 비밀번호가 존재하지 않는다.
 * 토큰 발급은 배포/common/app/src/azureToken.js 와 동일한 방식으로 구현한다.
 */
@Injectable()
export class DbService implements OnModuleInit {
  private readonly logger = new Logger(DbService.name);
  private readonly pool: Pool;

  constructor() {
    const mode = resolveAuthMode(process.env);
    this.pool = new Pool({
      host: process.env.DB_HOST ?? 'localhost',
      port: Number(process.env.DB_PORT ?? 5432),
      database: process.env.DB_NAME ?? 'appdb',
      user: process.env.DB_USER ?? 'appuser',
      password: mode === 'entra' ? async (): Promise<string> => this.entraToken() : (process.env.DB_PASSWORD ?? ''),
      max: Number(process.env.DB_POOL_MAX ?? 5),
      connectionTimeoutMillis: 5000,
      ssl: mode === 'entra' || String(process.env.DB_SSL ?? 'false').toLowerCase() === 'true'
        ? { rejectUnauthorized: false }
        : undefined,
    });
    // 오류 메시지에 자격 증명이 섞여 나가지 않도록 메시지만 남긴다
    this.pool.on('error', (e: Error) => this.logger.error(`pool error: ${e.message}`));
  }

  async onModuleInit(): Promise<void> {
    try {
      await this.ensureSchema();
    } catch (e) {
      // 기동 자체를 막지 않는다 — 준비 여부는 /readyz 가 판단한다
      this.logger.warn(`스키마 준비 실패 — /readyz 가 503 을 반환합니다: ${(e as Error).message}`);
    }
  }

  /** 워크로드 ID 토큰을 받아 온다. 실패 시 비밀번호로 대체하지 않는다. */
  private async entraToken(): Promise<string> {
    const fs = await import('node:fs/promises');
    const tokenFile = process.env.AZURE_FEDERATED_TOKEN_FILE ?? '';
    const assertion = (await fs.readFile(tokenFile, 'utf8')).trim();
    const authority = (process.env.AZURE_AUTHORITY_HOST ?? 'https://login.microsoftonline.com/').replace(/\/?$/, '/');
    const url = `${authority}${process.env.AZURE_TENANT_ID}/oauth2/v2.0/token`;
    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: process.env.AZURE_CLIENT_ID ?? '',
      scope: 'https://ossrdbms-aad.database.windows.net/.default',
      client_assertion_type: 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
      client_assertion: assertion,
    });
    const res = await fetch(url, { method: 'POST', body });
    if (!res.ok) {
      throw new Error(`Entra 토큰 교환 실패: HTTP ${res.status}`);
    }
    const json = (await res.json()) as { access_token?: string };
    if (!json.access_token) {
      throw new Error('Entra 응답에 access_token 이 없습니다.');
    }
    return json.access_token;
  }

  async ensureSchema(): Promise<void> {
    await this.pool.query(`
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

  async ping(): Promise<boolean> {
    const r = await this.pool.query('SELECT 1 AS ok');
    return r.rows[0]?.ok === 1;
  }

  async withClient<T>(fn: (c: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      return await fn(client);
    } finally {
      client.release();
    }
  }

  get raw(): Pool {
    return this.pool;
  }
}
