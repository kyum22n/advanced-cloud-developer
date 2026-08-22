# nginx-unprivileged — 캐시·pid 디렉터리가 이미 비루트로 쓰기 가능하게 구성되어 있다
# (일반 nginx:alpine 은 /var/cache/nginx 가 root 소유라 비루트로 시작하면 mkdir 권한 오류가 난다)
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime
# 정적 자산만 담는다 — 빌드 단계가 필요 없는 것이 이 구현의 장점이다
COPY public/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/templates/default.conf.template
ENV API_UPSTREAM=myapp:8080
EXPOSE 8080
# 숫자 UID 를 지정한다 — runAsNonRoot 검증기가 이름을 정적으로 확인하지 못해 CreateContainerConfigError 가 난다
USER 101
