# 멀티스테이지 — 런타임 이미지에는 devDependencies·빌드 도구를 포함하지 않는다
#
# Node 22 이상 고정: better-sqlite3@13은 Node >=22 가 필요하다. node:20 이미지로 빌드했을 때
# ABI 불일치로 DB 오픈 시점에 세그폴트(exit 139)가 발생하는 것을 실제로 확인했다.
# 베이스는 -slim(Debian/glibc)을 쓴다 — -alpine(musl)에서도 같은 세그폴트를 재현했었다(같은 근본 원인).
FROM node:22-slim AS deps
WORKDIR /app
# better-sqlite3 프리빌드가 없을 경우 소스에서 빌드할 수 있도록 최소 빌드 도구를 둔다(런타임에는 포함 안 함)
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json* ./
RUN npm install --omit=dev --no-audit --no-fund

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
# 비루트 사용자로 실행 (공급망·런타임 보안 기본). 숫자 UID로 생성한다 —
# k8s securityContext.runAsNonRoot는 이름이 아니라 숫자 UID로만 non-root를 검증한다.
RUN groupadd -g 1001 app && useradd -u 1001 -g app -M -s /usr/sbin/nologin app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY server.js ./
COPY src ./src
COPY public ./public
# SQLite 파일(data/app.db)을 쓸 디렉터리 — 비루트 사용자가 쓸 수 있어야 한다
RUN mkdir -p /app/data && chown -R 1001:1001 /app/data
USER 1001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server.js"]
