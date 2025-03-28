FROM ghcr.io/graalvm/graalvm-ce:latest

WORKDIR /app

COPY . .

RUN ./mvnw clean package -Pnative native:compile -DskipTests

EXPOSE 8080

CMD ["/app/target/spring-boot-graalvm"]
