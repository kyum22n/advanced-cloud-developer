# vLLM 이미지 — 가중치는 넣지 않는다(이미지 경량 유지 · 02 §3)
# 베이스 태그를 latest 로 두지 말 것: 어느 날 올라가면서 재현 불가능한 장애가 난다.
FROM vllm/vllm-openai:VLLM_VERSION_PLACEHOLDER

USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /models && chown -R 1000:1000 /models

# 비루트 실행
USER 1000
EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
