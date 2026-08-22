#!/usr/bin/env bash
# 가중치를 노드 로컬 캐시로 가져온 뒤 vLLM 을 기동한다.
#
# 인증: 워크로드 ID — 저장소 키를 쓰지 않는다(설계/공통/07).
#       azcopy/az 가 AZURE_CLIENT_ID·AZURE_FEDERATED_TOKEN_FILE 을 자동으로 사용한다.
set -euo pipefail

CACHE_DIR="${MODEL_CACHE_DIR:-/models}"
MODEL_DIR="${CACHE_DIR}/$(basename "${MODEL_ID}")"

if [ -d "${MODEL_DIR}" ] && [ -n "$(ls -A "${MODEL_DIR}" 2>/dev/null)" ]; then
  echo "[entrypoint] 캐시 적중 — 다운로드를 건너뜁니다: ${MODEL_DIR}"
else
  echo "[entrypoint] 가중치를 내려받습니다 (최초 1회, 수 분 소요)"
  mkdir -p "${MODEL_DIR}"
  # azcopy 는 워크로드 ID 를 자동 인식한다
  azcopy login --login-type workload-identity
  azcopy copy "${MODEL_BLOB_URL}/*" "${MODEL_DIR}" --recursive=true
fi

echo "[entrypoint] vLLM 을 기동합니다 (dtype=${DTYPE} tp=${TENSOR_PARALLEL_SIZE})"
exec python3 -m vllm.entrypoints.openai.api_server \
  --model "${MODEL_DIR}" \
  --served-model-name "${MODEL_ID}" \
  --host 0.0.0.0 --port 8000 \
  --dtype "${DTYPE}" \
  --kv-cache-dtype "${KV_CACHE_DTYPE}" \
  --max-model-len "${MAX_MODEL_LEN}" \
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
  --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}" \
  --disable-log-requests
