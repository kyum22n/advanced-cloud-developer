# -*- coding: utf-8 -*-
"""Azure 소매가 API 로 GPU VM 단가를 조회한다.

prices.azure.com 은 공개 API 로 인증이 필요 없다 — 그래서 이 계산은 누구나 재현할 수 있다.
문서에 가격을 박아 두지 않고 이 스크립트를 두는 이유는, 가격이 수시로 바뀌기 때문이다.

    python price_check.py [--region koreacentral] [--currency USD]
"""

from __future__ import annotations

import argparse
import collections
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API = "https://prices.azure.com/api/retail/prices"

TARGET_SKUS = [
    "Standard_NV36ads_A10_v5",
    "Standard_NV72ads_A10_v5",
    "Standard_NC24ads_A100_v4",
    "Standard_NC48ads_A100_v4",
    "Standard_NC96ads_A100_v4",
    "Standard_NC40ads_H100_v5",
    "Standard_NC80adis_H100_v5",
    "Standard_ND96isr_H100_v5",
]

GPUS_PER_NODE = {
    "Standard_NV36ads_A10_v5": 1, "Standard_NV72ads_A10_v5": 2,
    "Standard_NC24ads_A100_v4": 1, "Standard_NC48ads_A100_v4": 2, "Standard_NC96ads_A100_v4": 4,
    "Standard_NC40ads_H100_v5": 1, "Standard_NC80adis_H100_v5": 2,
    "Standard_ND96isr_H100_v5": 8,
}

HOURS = {"1 Year": 8760, "3 Years": 26280, "5 Years": 43800}


def fetch(query: str, max_retries: int = 4) -> list[dict]:
    """페이지를 모두 따라가며 항목을 모은다.

    공개 API 라 인증은 없지만 호출 빈도 제한(429)이 있다.
    지수 백오프로 재시도해 일시적 제한을 흡수한다.
    """
    url = f"{API}?$filter={urllib.parse.quote(query)}"
    items: list[dict] = []
    while url:
        for attempt in range(max_retries):
            try:
                with urllib.request.urlopen(url, timeout=60) as res:  # noqa: S310
                    data = json.load(res)
                break
            except urllib.error.HTTPError as exc:
                if exc.code == 429 and attempt < max_retries - 1:
                    wait = 2 ** (attempt + 1)
                    print(f"  [재시도] 호출 제한(429) — {wait}초 대기 후 재시도 ({attempt + 1}/{max_retries - 1})")
                    time.sleep(wait)
                    continue
                raise
        items += data.get("Items", [])
        url = data.get("NextPageLink")
    return items


def classify(item: dict) -> str | None:
    """가격 종류를 판정한다."""
    meter = item.get("meterName", "")
    if item.get("productName", "").endswith("Windows"):
        return None
    if "Spot" in meter:
        return "Spot"
    if "Low Priority" in meter:
        return "LowPriority"
    if item["type"] == "Reservation":
        return "RI:" + str(item.get("reservationTerm"))
    if item["type"] == "Consumption":
        return "OnDemand"
    return None


def main() -> int:
    """단가를 조회해 표로 출력하고 리포트를 남긴다."""
    parser = argparse.ArgumentParser(description="Azure GPU VM 단가 조회")
    parser.add_argument("--region", default="koreacentral")
    parser.add_argument("--currency", default="USD")
    args = parser.parse_args()

    query = f"serviceName eq 'Virtual Machines' and armRegionName eq '{args.region}'"
    try:
        items = fetch(query)
    except urllib.error.HTTPError as exc:
        if exc.code == 429:
            print("[중단] Azure 소매가 API 호출 제한(429)에 걸렸습니다. 잠시 뒤 다시 실행하세요.")
        else:
            print(f"[중단] 가격 조회 실패: HTTP {exc.code}")
        return 1
    except Exception as exc:  # noqa: BLE001
        print(f"[중단] 가격 조회 실패: {exc}")
        print("  네트워크(프록시) 설정을 확인하세요. 이 API 는 인증이 필요 없습니다.")
        return 1

    prices: dict[str, dict[str, float]] = collections.defaultdict(dict)
    for item in items:
        sku = item.get("armSkuName", "")
        if sku not in TARGET_SKUS:
            continue
        kind = classify(item)
        if kind:
            prices[sku][kind] = item["retailPrice"]

    stamp_utc = datetime.now(timezone.utc)
    print("=" * 104)
    print(f"Azure GPU VM 단가 — {args.region} · Linux · {args.currency} · 조회 {stamp_utc:%Y-%m-%d %H:%M UTC}")
    print("=" * 104)
    header = f"{'SKU':<30}{'GPU':>4}{'온디맨드':>11}{'Spot':>11}{'1년(환산)':>12}{'3년(환산)':>12}{'Spot/GPU':>11}"
    print(header)
    print("-" * 104)

    rows = []
    for sku in TARGET_SKUS:
        p = prices.get(sku)
        if not p:
            print(f"{sku:<30}   (이 리전에 가격 정보 없음)")
            continue
        gpus = GPUS_PER_NODE.get(sku, 1)
        od = p.get("OnDemand")
        spot = p.get("Spot") or p.get("LowPriority")
        r1 = p.get("RI:1 Year")
        r3 = p.get("RI:3 Years")
        r1h = r1 / HOURS["1 Year"] if r1 else None
        r3h = r3 / HOURS["3 Years"] if r3 else None
        fmt = lambda v: f"{v:.3f}" if v else "-"  # noqa: E731
        spot_per_gpu = spot / gpus if spot else None
        print(f"{sku:<30}{gpus:>4}{fmt(od):>11}{fmt(spot):>11}{fmt(r1h):>12}{fmt(r3h):>12}{fmt(spot_per_gpu):>11}")
        rows.append({
            "sku": sku, "gpusPerNode": gpus, "onDemand": od, "spot": spot,
            "reserved1yHourly": round(r1h, 4) if r1h else None,
            "reserved3yHourly": round(r3h, 4) if r3h else None,
            "spotDiscountPct": round(100 * (1 - spot / od), 1) if od and spot else None,
            "spotPerGpu": round(spot_per_gpu, 4) if spot_per_gpu else None,
        })

    print()
    print("  * 예약 가격은 총 선불액이므로 1년=8,760시간 · 3년=26,280시간으로 나눠 환산했습니다.")
    print("  * 총액이 아니라 'GPU 1장당 단가'로 비교하세요(03 §4-1).")
    print("  * 할인 계약(EA/CSP)이 있으면 실제 청구액은 더 낮습니다.")

    out = Path(__file__).resolve().parent / "reports"
    out.mkdir(exist_ok=True)
    name = f"price_{stamp_utc:%Y%m%d_%H%M%S}.json"
    (out / name).write_text(json.dumps({
        "kind": "price", "region": args.region, "currency": args.currency,
        "queriedAt": stamp_utc.isoformat(), "rows": rows,
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n리포트: {out / name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
