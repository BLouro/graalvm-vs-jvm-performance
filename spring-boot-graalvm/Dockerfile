FROM ghcr.io/graalvm/graalvm-community:17 AS builder

WORKDIR /app

COPY . .

RUN ./mvnw clean package -Pnative native:compile -DskipTests

FROM debian:bookworm-slim

WORKDIR /app

COPY --from=builder /app/target/spring-boot-graalvm /app/spring-boot-graalvm

EXPOSE 8080

ENTRYPOINT ["/app/spring-boot-graalvm", "-XX:MaximumHeapSizePercent=75"]
