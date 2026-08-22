# -*- coding: utf-8 -*-
"""VRAM·GPU 수 계산기.

model.json 에 채운 제원으로 «몇 장이 필요한가»를 계산한다.
확인하지 않은 값(null)이 있으면 계산을 거부한다 — 추정값으로 GPU 수를 정하면
비용이 몇 배로 어긋나기 때문이다.

    python sizing.py [--dtype fp8] [--concurrent-tokens 16384]
"""

from __future__ import annotations

import argparse
import json
import math
from datetime import datetime, timezone
from pathlib import Path

CONFIG_DIR = Path(__file__).resolve().parent.parent
MODEL_JSON = CONFIG_DIR / "model.json"

BYTES_PER_PARAM = {"bf16": 2.0, "fp16": 2.0, "fp8": 1.0, "int8": 1.0, "int4-awq": 0.5, "int4": 0.5}

# 참고용 GPU VRAM (GB) — 실제 값은 SKU 문서로 확인할 것
GPU_VRAM_GB = {
    "Standard_NC24ads_A100_v4": (1, 80),
    "Standard_NC48ads_A100_v4": (2, 80),
    "Standard_NC96ads_A100_v4": (4, 80),
    "Standard_NC40ads_H100_v5": (1, 94),
    "Standard_NC80adis_H100_v5": (2, 94),
    "Standard_ND96isr_H100_v5": (8, 80),
    "Standard_NV36ads_A10_v5": (1, 24),
    "Standard_NV72ads_A10_v5": (2, 24),
}

OVERHEAD_RATIO = 1.08  # 활성화·단편화·CUDA 컨텍스트


def load_model() -> dict:
    """모델 제원을 읽는다."""
    return json.loads(MODEL_JSON.read_text(encoding="utf-8"))


def require(arch: dict, keys: list[str]) -> list[str]:
    """확인되지 않은 항목을 돌려준다."""
    return [k for k in keys if arch.get(k) is None]


def weights_gb(total_params_b: float, dtype: str) -> float:
    """가중치 크기(GB). MoE 라도 총 파라미터가 모두 VRAM 에 올라간다."""
    return total_params_b * 1e9 * BYTES_PER_PARAM[dtype] / (1024 ** 3)


def kv_per_token_bytes(layers: int, kv_heads: int, head_dim: int, dtype: str) -> float:
    """토큰 하나당 KV 캐시 바이트. K 와 V 두 벌이므로 2배."""
    return 2 * layers * kv_heads * head_dim * BYTES_PER_PARAM[dtype]


def main() -> int:
    """계산을 수행하고 리포트를 남긴다."""
    parser = argparse.ArgumentParser(description="VRAM·GPU 수 계산")
    parser.add_argument("--dtype", default=None, help="bf16 | fp8 | int4-awq")
    parser.add_argument("--kv-dtype", default=None)
    parser.add_argument("--concurrent-tokens", type=int, default=None)
    parser.add_argument("--sku", default=None)
    args = parser.parse_args()

    cfg = load_model()
    arch = cfg["architecture"]
    serving = cfg["serving"]

    missing = require(arch, ["totalParamsB", "numLayers", "numKeyValueHeads", "headDim", "maxContextTokens"])
    if missing:
        print("[중단] 모델 제원이 확인되지 않았습니다:", ", ".join(missing))
        print()
        print("  공식 모델 카드와 config.json 에서 값을 확인해 model.json 에 채우세요.")
        print("  추정값으로 계산하면 GPU 수가 몇 배로 어긋날 수 있어 의도적으로 중단합니다.")
        print(f"  파일: {MODEL_JSON}")
        return 2

    if serving.get("engineSupportsArchitecture") is not True:
        print("[경고] serving.engineSupportsArchitecture 가 true 가 아닙니다.")
        print("  vLLM 릴리스 노트에서 이 아키텍처 지원 여부를 먼저 확인하세요 — 지원되지 않으면 기동 자체가 실패합니다.")
        print()

    dtype = args.dtype or serving.get("dtype", "fp8")
    kv_dtype = args.kv_dtype or serving.get("kvCacheDtype", dtype)
    concurrent = args.concurrent_tokens or serving.get("maxConcurrentTokens", 16384)
    util = float(serving.get("gpuMemoryUtilization", 0.90))

    if dtype not in BYTES_PER_PARAM:
        print(f"[중단] 알 수 없는 정밀도: {dtype} (가능: {', '.join(BYTES_PER_PARAM)})")
        return 2

    w = weights_gb(float(arch["totalParamsB"]), dtype)
    kv_token = kv_per_token_bytes(
        int(arch["numLayers"]), int(arch["numKeyValueHeads"]), int(arch["headDim"]), kv_dtype
    )
    kv_total = kv_token * concurrent / (1024 ** 3)
    need = (w + kv_total) * OVERHEAD_RATIO

    print("=" * 72)
    print(f"VRAM 산정 — {cfg['modelId']}  (정밀도 {dtype} · KV {kv_dtype})")
    print("=" * 72)
    print(f"  총 파라미터            : {arch['totalParamsB']} B" + (
        f"  (활성 {arch.get('activeParamsB')} B — MoE)" if arch.get("isMoE") else ""))
    print(f"  가중치                 : {w:8.1f} GB")
    print(f"  KV 캐시(토큰당)        : {kv_token / 1024:8.1f} KB")
    print(f"  KV 캐시(동시 {concurrent:,} 토큰) : {kv_total:8.1f} GB")
    print(f"  오버헤드({(OVERHEAD_RATIO - 1) * 100:.0f}%)         : {(w + kv_total) * (OVERHEAD_RATIO - 1):8.1f} GB")
    print(f"  {'필요 VRAM 합계':<22} : {need:8.1f} GB")
    print()

    if arch.get("isMoE"):
        print("  [주의] MoE 모델입니다 — 연산량은 활성 파라미터를 따르지만")
        print("         메모리는 '총 파라미터'를 따릅니다. 위 계산은 총 파라미터 기준입니다.")
        print()

    skus = [args.sku] if args.sku else list(GPU_VRAM_GB)
    print(f"{'SKU':<30}{'GPU':>5}{'VRAM/GPU':>10}{'가용':>9}{'필요 노드':>10}")
    print("-" * 72)
    rows = []
    for sku in skus:
        if sku not in GPU_VRAM_GB:
            continue
        gpus, vram = GPU_VRAM_GB[sku]
        usable_per_node = gpus * vram * util
        nodes = math.ceil(need / usable_per_node) if usable_per_node else 0
        fits_single = need <= usable_per_node
        mark = " ← 한 노드에 들어감" if fits_single else ""
        print(f"{sku:<30}{gpus:>5}{vram:>9}GB{usable_per_node:>8.0f}GB{nodes:>10}{mark}")
        rows.append({"sku": sku, "gpusPerNode": gpus, "vramPerGpuGb": vram,
                     "usablePerNodeGb": round(usable_per_node, 1), "nodesNeeded": nodes,
                     "fitsSingleNode": fits_single})
    print()
    print("  * 가용 = GPU수 × VRAM × gpuMemoryUtilization(%.2f)" % util)
    print("  * '한 노드에 들어감' 이면 텐서 병렬이 불필요합니다 — 통신 병목과 구성 복잡도가 사라집니다(02 §5).")
    print("  * VRAM 값은 참고치입니다. 실제 SKU 문서로 확인하세요.")

    out = Path(__file__).resolve().parent / "reports"
    out.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    payload = {
        "kind": "sizing", "modelId": cfg["modelId"], "dtype": dtype, "kvDtype": kv_dtype,
        "concurrentTokens": concurrent, "gpuMemoryUtilization": util,
        "weightsGb": round(w, 1), "kvTotalGb": round(kv_total, 1), "needGb": round(need, 1),
        "candidates": rows,
    }
    (out / f"sizing_{stamp}.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n리포트: {out / f'sizing_{stamp}.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
