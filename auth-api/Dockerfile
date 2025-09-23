FROM golang:1.23-alpine

# Install git for dependencies
RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Copy source code
COPY . .

# Initialize go modules and get dependencies based on imports
RUN go mod init auth-api
RUN go get github.com/golang-jwt/jwt/v4
RUN go get github.com/labstack/echo/v4
RUN go get github.com/labstack/echo/v4/middleware
RUN go get github.com/labstack/gommon/log
RUN go mod tidy

# Build the application
RUN CGO_ENABLED=0 go build -o auth-api .

EXPOSE 8000

# Environment variables
ENV AUTH_API_PORT=8000

CMD ["./auth-api"]