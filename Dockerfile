FROM maven:3.8-openjdk-8 AS backend-build
WORKDIR /app
COPY backend/pom.xml .
RUN mvn dependency:go-offline -B
COPY backend/src ./src
RUN mvn clean package -DskipTests

FROM node:18-alpine AS frontend-build
WORKDIR /app
COPY frontend/package*.json ./
RUN npm install
COPY frontend .
RUN npm run build

FROM openjdk:8-jdk-alpine
WORKDIR /app

RUN apk add --no-cache nginx

COPY --from=backend-build /backend/target/*.jar /app/backend.jar
COPY --from=frontend-build /frontend/dist /usr/share/nginx/html
COPY nginx-standalone.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /app/data && \
    echo '#!/bin/sh' > /app/start.sh && \
    echo 'nginx' >> /app/start.sh && \
    echo 'java -jar /app/backend.jar' >> /app/start.sh && \
    chmod +x /app/start.sh

EXPOSE 10012

ENV DATA_DIR=/app/data

CMD ["/app/start.sh"]
