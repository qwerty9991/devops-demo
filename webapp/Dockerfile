#### Step 1: Build the application
FROM maven:3.9.9-eclipse-temurin-23 AS builder
WORKDIR /app
COPY ./webapp_project/ .
RUN mvn clean package -DskipTests

# Step 2: Create the runtime image
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/webapp-0.0.1-SNAPSHOT.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
