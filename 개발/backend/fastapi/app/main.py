"""FastAPI 애플리케이션. 계약은 개발/공통/openapi.yaml 을 따른다."""

from __future__ import annotations

import logging
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Header, Request
from fastapi.responses import JSONResponse

from app import db
from app.authmode import auth_info
from app.summary import ItemLike, dedupe_by_id, summarize_by_week

logger = logging.getLogger(__name__)
MAX_ROWS = 200


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """기동 시 스키마를 준비한다. 실패해도 앱은 뜨고 /readyz 가 503 을 돌려준다."""
    try:
        await db.ensure_schema()
    except Exception as exc:  # noqa: BLE001
        logger.warning("스키마 준비 실패 — /readyz 가 503 을 반환합니다: %s", exc)
    yield


app = FastAPI(title="나만의 업무 앱", version="1.0.0", lifespan=lifespan)


def _row_to_item(row: dict[str, Any]) -> ItemLike:
    return ItemLike(
        id=int(row["id"]),
        title=str(row["title"]),
        amount=float(row["amount"]),
        createdAt=row["created_at"].isoformat(),
    )


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    """생존 프로브. 의존성을 확인하지 않는다."""
    return {"status": "ok", "env": os.environ.get("APP_ENV", "dev")}


@app.get("/readyz")
async def readyz() -> JSONResponse:
    """준비 프로브. DB 연결을 실제로 확인한다."""
    try:
        if await db.ping():
            return JSONResponse({"status": "ready"})
    except Exception as exc:  # noqa: BLE001
        logger.warning("readyz 실패: %s", exc)
    return JSONResponse({"status": "not-ready", "reason": "database"}, status_code=503)


@app.get("/version")
async def version() -> dict[str, Any]:
    """배포 버전·환경·인증 방식. 자격 증명 값은 담지 않는다."""
    return {
        "version": os.environ.get("APP_VERSION", "0.0.0"),
        "env": os.environ.get("APP_ENV", "dev"),
        "auth": auth_info(os.environ),
    }


@app.get("/api/items")
async def list_items(limit: int = MAX_ROWS) -> dict[str, Any]:
    """항목 목록(최신순 최대 200건)."""
    bounded = min(max(limit, 1), MAX_ROWS)
    rows = await db.fetch_all(
        "SELECT id, title, amount, created_at FROM items ORDER BY id DESC LIMIT %s", (bounded,)
    )
    items = dedupe_by_id(_row_to_item(r) for r in rows)
    return {"count": len(items), "items": items}


@app.post("/api/items", status_code=201)
async def create_item(request: Request, x_user: str | None = Header(default=None)) -> JSONResponse:
    """항목 등록. 검증 실패는 400 으로 매핑된다."""
    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        payload = {}
    title = payload.get("title") if isinstance(payload, dict) else None
    trimmed = title.strip() if isinstance(title, str) else ""
    if trimmed == "":
        return JSONResponse({"error": "title 은 필수이며 빈 문자열일 수 없습니다."}, status_code=400)
    raw_amount: object = payload.get("amount") if isinstance(payload, dict) else None
    if raw_amount is None or raw_amount == "":
        amount = 0.0
    elif isinstance(raw_amount, bool) or not isinstance(raw_amount, int | float | str):
        return JSONResponse({"error": "amount 는 숫자여야 합니다."}, status_code=400)
    else:
        try:
            amount = float(raw_amount)
        except ValueError:
            return JSONResponse({"error": "amount 는 숫자여야 합니다."}, status_code=400)

    saved = await db.execute(
        "INSERT INTO items (title, amount) VALUES (%s, %s) RETURNING id, title, amount, created_at",
        (trimmed, amount),
    )
    if saved is None:
        return JSONResponse({"error": "처리 중 오류가 발생했습니다."}, status_code=500)
    item = _row_to_item(saved)
    await db.execute(
        "INSERT INTO audit_log (actor, action, target) VALUES (%s, %s, %s)",
        (x_user or "anonymous", "create", f"item:{item['id']}"),
    )
    return JSONResponse(dict(item), status_code=201)


@app.get("/api/summary")
async def summary() -> dict[str, Any]:
    """주차별 집계."""
    rows = await db.fetch_all("SELECT id, title, amount, created_at FROM items ORDER BY id ASC")
    return {"weeks": summarize_by_week([_row_to_item(r) for r in rows])}
