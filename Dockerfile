# Define base image version
ARG VALKEY_VERSION=8-alpine
ARG METRICS_EXPORTER_VERSION=develop

FROM ghcr.io/lumeweb/akash-metrics-exporter:${METRICS_EXPORTER_VERSION} AS metrics-exporter
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

# Environment variables for S3 backup configuration
ENV ENABLE_BACKUP=false
ENV S3_ENDPOINT=""
ENV S3_ACCESS_KEY=""
ENV S3_SECRET_KEY=""
ENV S3_BUCKET=""
ENV BACKUP_RETENTION_DAYS=7
ENV BACKUP_PREFIX="valkey-backup"
ENV BACKUP_SCHEDULE="0 0 * * *"

# Copy our scripts
COPY backup.sh /usr/local/bin/
COPY entrypoint.sh /entrypoint.sh
COPY --from=metrics-exporter /usr/bin/metrics-exporter /usr/bin/akash-metrics-exporter

ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 6379
CMD ["valkey-server"]