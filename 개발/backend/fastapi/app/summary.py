"""주차 집계 — 외부 의존이 없는 순수 로직(U-A-01~05)."""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from datetime import datetime, timezone
from typing import TypedDict


class ItemLike(TypedDict):
    """집계 입력."""

    id: int
    title: str
    amount: float
    createdAt: str


class WeekSummary(TypedDict):
    """집계 결과."""

    week: str
    count: int
    amount: float


def iso_week(value: str | datetime) -> str:
    """ISO 8601 주차 문자열(YYYY-Www)을 만든다."""
    moment = datetime.fromisoformat(value.replace("Z", "+00:00")) if isinstance(value, str) else value
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    year, week, _ = moment.astimezone(timezone.utc).isocalendar()
    return f"{year}-W{week:02d}"


def summarize_by_week(items: Sequence[ItemLike]) -> list[WeekSummary]:
    """주차별 건수·금액을 집계한다. 빈 입력은 예외가 아니라 빈 결과다."""
    if not isinstance(items, list | tuple):
        raise TypeError("items must be a sequence")
    acc: dict[str, WeekSummary] = {}
    for item in items:
        week = iso_week(item["createdAt"])
        cur = acc.setdefault(week, WeekSummary(week=week, count=0, amount=0.0))
        cur["count"] += 1
        cur["amount"] += float(item["amount"] or 0)
    return sorted(acc.values(), key=lambda w: w["week"])


def dedupe_by_id(items: Iterable[ItemLike]) -> list[ItemLike]:
    """같은 id 가 여러 번 나오면 마지막 값만 남긴다."""
    by_id: dict[int, ItemLike] = {}
    for item in items:
        by_id[int(item["id"])] = item
    return list(by_id.values())
