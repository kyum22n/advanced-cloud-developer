# -*- coding: utf-8 -*-
"""손익분기 계산 — 관리형 API vs 자체 배포.

'자체 배포가 싸다'는 직관은 사용률이 충분히 높을 때만 참이다.
이 스크립트는 그 경계를 숫자로 보여 준다.

    python breakeven.py --in-tokens 200 --out-tokens 40 \
        --api-in 0.3 --api-out 1.2 --gpu-hourly 0.916 --hours-per-month 198
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    """두 방식의 월 비용을 비교한다."""
    p = argparse.ArgumentParser(description="관리형 API vs 자체 배포 손익분기")
    p.add_argument("--in-tokens", type=float, required=True, help="월 입력 토큰 (백만 단위)")
    p.add_argument("--out-tokens", type=float, required=True, help="월 출력 토큰 (백만 단위)")
    p.add_argument("--api-in", type=float, required=True, help="관리형 API 입력 단가 (USD / 1M)")
    p.add_argument("--api-out", type=float, required=True, help="관리형 API 출력 단가 (USD / 1M)")
    p.add_argument("--gpu-hourly", type=float, required=True, help="GPU 노드 시간당 단가 (USD)")
    p.add_argument("--gpu-count", type=int, default=1, help="노드 수")
    p.add_argument("--hours-per-month", type=float, default=730, help="월 가동 시간 (730=24시간 상시)")
    p.add_argument("--overhead", type=float, default=40, help="저장소·관측·ACR 등 부대비용 (USD/월)")
    args = p.parse_args()

    api_cost = args.in_tokens * args.api_in + args.out_tokens * args.api_out
    gpu_cost = args.gpu_count * args.gpu_hourly * args.hours_per_month
    self_cost = gpu_cost + args.overhead
    total_tokens_m = args.in_tokens + args.out_tokens

    print("=" * 68)
    print("손익분기 비교 — 월 기준 (USD)")
    print("=" * 68)
    print(f"  월 토큰            : 입력 {args.in_tokens:,.0f}M · 출력 {args.out_tokens:,.0f}M (합 {total_tokens_m:,.0f}M)")
    print()
    print(f"  ① 관리형 API       : {api_cost:10,.2f}")
    print(f"       입력 {args.in_tokens:,.0f}M × {args.api_in} = {args.in_tokens * args.api_in:,.2f}")
    print(f"       출력 {args.out_tokens:,.0f}M × {args.api_out} = {args.out_tokens * args.api_out:,.2f}")
    print()
    print(f"  ② 자체 배포        : {self_cost:10,.2f}")
    print(f"       GPU {args.gpu_count}대 × {args.gpu_hourly}/h × {args.hours_per_month:,.0f}h = {gpu_cost:,.2f}")
    print(f"       부대비용 = {args.overhead:,.2f}")
    print()

    if total_tokens_m > 0:
        print(f"  비용/1M 토큰       : 관리형 {api_cost / total_tokens_m:6.3f}  ·  자체 {self_cost / total_tokens_m:6.3f}")
        print()

    diff = api_cost - self_cost
    if diff > 0:
        print(f"  → 자체 배포가 월 {diff:,.2f} USD 유리합니다.")
    else:
        print(f"  → 관리형 API 가 월 {-diff:,.2f} USD 유리합니다.")

    # 손익분기 토큰 수 (입출력 비율을 유지한다고 가정)
    if api_cost > 0 and total_tokens_m > 0:
        api_unit = api_cost / total_tokens_m
        breakeven_m = self_cost / api_unit
        print(f"  → 손익분기 지점    : 월 약 {breakeven_m:,.0f}M 토큰 (현재 {total_tokens_m:,.0f}M)")

    print()
    print("  [주의] 관리형 API 단가는 서비스·모델·계약마다 크게 다릅니다.")
    print("         반드시 실제 계약 단가를 넣어 다시 계산하세요.")
    print("  [주의] 자체 배포에는 운영 인건비가 포함되어 있지 않습니다.")

    out = Path(__file__).resolve().parent / "reports"
    out.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    (out / f"breakeven_{stamp}.json").write_text(json.dumps({
        "kind": "breakeven", "inputs": vars(args),
        "apiCostUsd": round(api_cost, 2), "selfCostUsd": round(self_cost, 2),
        "advantage": "self" if diff > 0 else "managed",
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n리포트: {out / f'breakeven_{stamp}.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
