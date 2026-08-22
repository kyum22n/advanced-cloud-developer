"""DB 접근. 연결 정보는 환경 변수로만 받는다 — 코드·이미지에 비밀을 두지 않는다."""

from __future__ import annotations

import logging
import os
from typing import Any

import psycopg
from psycopg.rows import dict_row

from app.authmode import resolve_auth_mode

logger = logging.getLogger(__name__)

SCHEMA_SQL = """
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
"""


async def _entra_token() -> str:
    """워크로드 ID 토큰을 Entra 액세스 토큰으로 교환한다.

    파드에 비밀번호도 클라이언트 시크릿도 없다 — 짧은 수명의 SA 토큰만 있다.
    """
    import httpx

    token_file = os.environ.get("AZURE_FEDERATED_TOKEN_FILE", "")
    with open(token_file, encoding="utf-8") as handle:  # noqa: ASYNC101
        assertion = handle.read().strip()
    authority = os.environ.get("AZURE_AUTHORITY_HOST", "https://login.microsoftonline.com/").rstrip("/")
    url = f"{authority}/{os.environ.get('AZURE_TENANT_ID', '')}/oauth2/v2.0/token"
    data = {
        "grant_type": "client_credentials",
        "client_id": os.environ.get("AZURE_CLIENT_ID", ""),
        "scope": "https://ossrdbms-aad.database.windows.net/.default",
        "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        "client_assertion": assertion,
    }
    async with httpx.AsyncClient(timeout=10) as client:
        res = await client.post(url, data=data)
    if res.status_code != 200:
        # 토큰 값이나 assertion 은 절대 로그에 남기지 않는다
        raise RuntimeError(f"Entra 토큰 교환 실패: HTTP {res.status_code}")
    token: str = res.json().get("access_token", "")
    if not token:
        raise RuntimeError("Entra 응답에 access_token 이 없습니다.")
    return token


async def build_conninfo() -> str:
    """환경에 맞는 접속 문자열을 만든다."""
    mode = resolve_auth_mode(os.environ)
    password = await _entra_token() if mode == "entra" else os.environ.get("DB_PASSWORD", "")
    sslmode = "require" if mode == "entra" or os.environ.get("DB_SSL", "false").lower() == "true" else "prefer"
    return (
        f"host={os.environ.get('DB_HOST', 'localhost')} "
        f"port={os.environ.get('DB_PORT', '5432')} "
        f"dbname={os.environ.get('DB_NAME', 'appdb')} "
        f"user={os.environ.get('DB_USER', 'appuser')} "
        f"password={password} "
        f"sslmode={sslmode} "
        f"connect_timeout=5"
    )


async def fetch_all(sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    """조회 전용 헬퍼."""
    conninfo = await build_conninfo()
    async with (
        await psycopg.AsyncConnection.connect(conninfo, row_factory=dict_row) as conn,
        conn.cursor() as cur,
    ):
        await cur.execute(sql, params)
        rows = await cur.fetchall()
    return list(rows)


async def execute(sql: str, params: tuple[Any, ...] = ()) -> dict[str, Any] | None:
    """변경 전용 헬퍼. RETURNING 이 있으면 첫 행을 돌려준다."""
    conninfo = await build_conninfo()
    async with (
        await psycopg.AsyncConnection.connect(conninfo, row_factory=dict_row) as conn,
        conn.cursor() as cur,
    ):
        await cur.execute(sql, params)
        row = await cur.fetchone() if cur.description else None
        await conn.commit()
    return dict(row) if row else None


async def ensure_schema() -> None:
    """기동 시 스키마를 보장한다(실습 범위. 운영은 마이그레이션 도구 권장)."""
    async with await psycopg.AsyncConnection.connect(await build_conninfo()) as conn:
        await conn.execute(SCHEMA_SQL)
        await conn.commit()


async def ping() -> bool:
    """DB 가 응답하는지 확인한다. /readyz 가 이 결과에 의존한다."""
    rows = await fetch_all("SELECT 1 AS ok")
    return bool(rows) and rows[0].get("ok") == 1
