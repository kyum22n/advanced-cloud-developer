# 큐 소비 · Saga 조정 · 감시
#
# ⚠️ 빌드 컨텍스트는 이 파일이 있는 폴더가 아니라 «services/» 다.
#    멀티모듈 Maven 프로젝트라 부모 POM 과 common-contract 가 필요하기 때문이다.
#
#    docker build -f workflow/Dockerfile -t acrdrone.azurecr.io/workflow:$GIT_SHA services/
#
# 규칙 (설계/09_보안_아이덴티티_설계서.md)
#   · 멀티스테이지    — 빌드 도구가 최종 이미지에 남지 않는다
#   · 비루트 실행     — SEC-09
#   · 태그 고정       — SEC-10. latest 금지
#   · 비밀 없음       — 이미지에 자격 증명을 굽지 않는다. 관리 ID 로 런타임에 토큰을 받는다

# ───────────────────────────────── 빌드 단계
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /build

# 의존성 캐시 — POM 만 먼저 복사해 소스 변경 시 재다운로드를 피한다
COPY pom.xml .
COPY common-contract/pom.xml common-contract/
COPY workflow/pom.xml workflow/
RUN mvn -B -q -pl common-contract,workflow -am dependency:go-offline

COPY common-contract/src common-contract/src
COPY workflow/src workflow/src
RUN mvn -B -q -pl workflow -am package -DskipTests

# ───────────────────────────────── 실행 단계
FROM eclipse-temurin:17.0.13_11-jre-alpine

RUN addgroup -S app && adduser -S -G app app
WORKDIR /app
COPY --from=build /build/workflow/target/*.jar /app/app.jar

USER app
EXPOSE 8082

# MaxRAMPercentage — 컨테이너 메모리 제한을 JVM 이 인식하게 한다.
# 이것이 없으면 JVM 이 호스트 전체 메모리를 기준으로 힙을 잡아 OOMKilled 가 난다.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+UseG1GC -XX:+ExitOnOutOfMemoryError"

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget -q -O - http://localhost:8082/actuator/health/liveness || exit 1

ENTRYPOINT ["sh","-c","exec java $JAVA_OPTS -jar /app/app.jar"]
