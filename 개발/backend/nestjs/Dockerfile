# 멀티스테이지 — 빌드 의존성을 최종 이미지에 남기지 않는다
FROM node:20-alpine AS build
WORKDIR /src
COPY package*.json tsconfig.json nest-cli.json ./
RUN npm ci
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:20-alpine AS runtime
WORKDIR /app
COPY --from=build /src/node_modules ./node_modules
COPY --from=build /src/dist ./dist
COPY --from=build /src/package.json ./package.json
# 비루트 실행 — node 이미지의 기본 사용자를 사용한다
USER node
EXPOSE 8080
CMD ["node", "dist/main.js"]
