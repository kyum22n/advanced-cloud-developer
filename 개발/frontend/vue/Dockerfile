# 멀티스테이지 — 빌드 도구를 최종 이미지에 남기지 않는다
FROM node:20-alpine AS build
WORKDIR /src
COPY package*.json vite.config.js index.html ./
RUN npm ci
COPY src ./src
RUN npm run build

FROM nginx:1.27-alpine AS runtime
COPY --from=build /src/dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/templates/default.conf.template
ENV API_UPSTREAM=myapp:8080
EXPOSE 8080
USER nginx
