# 멀티스테이지 — 빌드 도구를 최종 이미지에 남기지 않는다
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
COPY pom.xml checkstyle.xml ./
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q package -DskipTests

FROM eclipse-temurin:17-jre-alpine AS runtime
# 비루트 실행 — 침해 시 피해 범위를 줄인다
RUN addgroup -S app && adduser -S app -G app
WORKDIR /app
COPY --from=build /src/target/myapp-1.0.0.jar app.jar
USER app
EXPOSE 8080
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+UseSerialGC"
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
