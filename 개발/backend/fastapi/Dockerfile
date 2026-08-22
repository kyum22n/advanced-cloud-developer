# 멀티스테이지 — 빌드 도구를 최종 이미지에 남기지 않는다
FROM python:3.11-slim AS build
WORKDIR /src
COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim AS runtime
# 비루트 실행 — 침해 시 피해 범위를 줄인다
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app
COPY --from=build /install /usr/local
COPY app ./app
# 숫자 UID 를 지정한다 — runAsNonRoot 검증기가 이름(appuser)을 정적으로 확인하지 못해 CreateContainerConfigError 가 난다
USER 10001
EXPOSE 8080
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
