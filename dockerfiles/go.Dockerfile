# Go base Dockerfile
FROM golang:1.23 AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app ./cmd/main.go

# Runtime
FROM cgr.dev/chainguard/static:latest AS runtime

COPY --from=builder /app /usr/local/bin/app

ENTRYPOINT ["/usr/local/bin/app"]
