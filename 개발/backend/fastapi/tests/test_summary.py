"""단위 테스트 — 설계/공통/06 의 U-A-01~05 에 대응한다."""

from __future__ import annotations

import pytest

from app.summary import ItemLike, dedupe_by_id, iso_week, summarize_by_week


def item(item_id: int, iso: str, amount: float) -> ItemLike:
    """테스트용 항목을 만든다."""
    return ItemLike(id=item_id, title=f"t{item_id}", amount=amount, createdAt=iso)


def test_u_a_01_same_week() -> None:
    """같은 주의 월요일과 일요일은 동일한 주차."""
    assert iso_week("2026-03-02T00:00:00Z") == iso_week("2026-03-08T23:59:59Z")


def test_u_a_02_summarize() -> None:
    """주차별 건수와 합계를 집계."""
    weeks = summarize_by_week(
        [
            item(1, "2026-03-02T00:00:00Z", 100),
            item(2, "2026-03-03T00:00:00Z", 200),
            item(3, "2026-03-10T00:00:00Z", 50),
        ]
    )
    assert len(weeks) == 2
    assert weeks[0]["count"] == 2
    assert weeks[0]["amount"] == 300


def test_u_a_03_empty() -> None:
    """빈 입력은 예외가 아니라 빈 결과."""
    assert summarize_by_week([]) == []


def test_u_a_04_type_error() -> None:
    """시퀀스가 아니면 TypeError."""
    with pytest.raises(TypeError):
        summarize_by_week(None)  # type: ignore[arg-type]


def test_u_a_05_dedupe() -> None:
    """같은 id 는 마지막 값만 남는다."""
    deduped = dedupe_by_id(
        [
            item(1, "2026-03-02T00:00:00Z", 10),
            item(1, "2026-03-02T00:00:00Z", 20),
            item(2, "2026-03-02T00:00:00Z", 30),
        ]
    )
    assert len(deduped) == 2
    assert deduped[0]["amount"] == 20
