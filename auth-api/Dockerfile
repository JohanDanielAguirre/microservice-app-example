# Auth API (Go)
# Build stage
FROM golang:1.18-alpine AS build
WORKDIR /app
ENV CGO_ENABLED=0
# Enable modules
ENV GO111MODULE=on
COPY . .
# Initialize modules if missing and fetch deps
RUN go mod init auth-api || true && go mod tidy
# Build static binary
RUN GOOS=linux GOARCH=amd64 go build -o /auth-api

# Final stage
FROM alpine:3.18
WORKDIR /app
COPY --from=build /auth-api /usr/local/bin/auth-api
EXPOSE 8000
ENTRYPOINT ["auth-api"]

