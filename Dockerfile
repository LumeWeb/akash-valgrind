# Define base image version
ARG VALKEY_VERSION=8-alpine
ARG METRICS_EXPORTER_VERSION=develop
ARG METRICS_REGISTRAR_VERSION=develop

FROM ghcr.io/lumeweb/akash-metrics-exporter:${METRICS_EXPORTER_VERSION} AS metrics-exporter
FROM ghcr.io/lumeweb/akash-metrics-registrar:${METRICS_REGISTRAR_VERSION} AS metrics-registrar

# Build redis_exporter
FROM golang:1.21-alpine AS redis-exporter
RUN CGO_ENABLED=0 go install github.com/oliver006/redis_exporter@latest

# Extend from valgrind
FROM valkey/valkey:${VALKEY_VERSION}

# Define build arguments (after FROM to be available during build)
ARG SUPERCRONIC_VERSION=0.2.33

# Install required packages
RUN apk add --no-cache \
    curl \
    wget \
    ca-certificates \
    supercronic \
    && rm -rf /var/cache/apk/*

# Install MinIO client
RUN wget https://dl.min.io/client/mc/release/linux-amd64/mc \
    && chmod +x mc \
    && mv mc /usr/local/bin/

# Install supercronic
RUN wget https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-amd64 -O /usr/local/bin/supercronic \
    && chmod +x /usr/local/bin/supercronic

# Copy binaries from build stages
COPY --from=metrics-exporter /usr/bin/metrics-exporter /usr/local/bin/akash-metrics-exporter
COPY --from=redis-exporter /go/bin/redis_exporter /usr/local/bin/
COPY --from=metrics-registrar /usr/bin/metrics-registrar /usr/local/bin/akash-metrics-registrar

# Copy our scripts
COPY backup.sh /usr/local/bin/
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["valkey-server"]
