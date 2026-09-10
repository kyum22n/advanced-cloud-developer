# Vue SPA — 정적 파일로 빌드해 nginx 로 서빙한다.
#
# 실제 운영에서는 이 이미지 대신 Storage 정적 웹사이트 + Front Door 를 쓴다
# (설계/05_API_게이트웨이_설계서.md §7). 이 Dockerfile 은 로컬·dev 용이다.

FROM node:22.12.0-alpine AS build
WORKDIR /src
COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund
COPY . .
RUN npm run build

FROM nginx:1.27.3-alpine
RUN addgroup -S app && adduser -S -G app app
COPY --from=build /src/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
RUN chown -R app:app /usr/share/nginx/html /var/cache/nginx /var/run
USER app
EXPOSE 8080
