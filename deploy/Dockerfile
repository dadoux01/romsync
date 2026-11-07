# syntax=docker/dockerfile:1
# Build from the repository root:
#   docker build -f deploy/Dockerfile -t romsync .

# 1. Web interface
FROM docker.io/library/node:24-alpine AS web
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ ./
RUN npm run build

# 2. Server, with the web interface embedded
FROM docker.io/library/golang:1.27-alpine AS server
WORKDIR /src/server
COPY server/go.mod server/go.sum ./
RUN go mod download
COPY server/ ./
COPY --from=web /src/web/dist/ ./internal/webui/dist/
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/romsync ./cmd/romsync \
 && mkdir -p /out/data

# 3. Minimal runtime image: static binary, no shell, non-root user (65532)
FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=server /out/romsync /usr/local/bin/romsync
COPY --from=server --chown=65532:65532 /out/data /data
ENV ROMSYNC_PORT=8080 \
    ROMSYNC_DATA_DIR=/data
EXPOSE 8080
VOLUME ["/data"]
USER 65532:65532
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/usr/local/bin/romsync", "healthcheck"]
ENTRYPOINT ["/usr/local/bin/romsync"]
