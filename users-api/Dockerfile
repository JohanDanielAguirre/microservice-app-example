# Users API (Spring Boot)
# Build stage
FROM maven:3.9.6-eclipse-temurin-11 AS build
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -q -DskipTests package

# Run stage
FROM eclipse-temurin:11-jre
WORKDIR /app
COPY --from=build /build/target/users-api-0.0.1-SNAPSHOT.jar /app/app.jar
EXPOSE 8083
ENV SERVER_PORT=8083
ENTRYPOINT ["java","-jar","/app/app.jar"]

