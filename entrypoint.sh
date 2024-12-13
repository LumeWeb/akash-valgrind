#!/bin/sh
set -e

# Generate Valkey config file
CONFIG_FILE="/usr/local/etc/valkey/valkey.conf"
mkdir -p "$(dirname "$CONFIG_FILE")"

# Essential Valkey settings with defaults
: "${VALKEY_PORT:=6379}"
: "${VALKEY_BIND:=0.0.0.0}"
: "${VALKEY_MAXMEMORY:=0}"  # 0 means no limit
: "${VALKEY_MAXMEMORY_POLICY:=noeviction}"
: "${VALKEY_APPENDONLY:=no}"
: "${VALKEY_REQUIREPASS:=}"

cat > "$CONFIG_FILE" << EOF
# Network
bind ${VALKEY_BIND}
port ${VALKEY_PORT}
protected-mode yes

# Memory Management
maxmemory ${VALKEY_MAXMEMORY}
maxmemory-policy ${VALKEY_MAXMEMORY_POLICY}

# Persistence
dir /data
dbfilename db.rdb
appendonly ${VALKEY_APPENDONLY}

# Security
EOF

# Only add requirepass if it's set
if [ -n "$VALKEY_REQUIREPASS" ]; then
    echo "requirepass ${VALKEY_REQUIREPASS}" >> "$CONFIG_FILE"
fi

# Start backup process if enabled
if [ "$ENABLE_BACKUP" = "true" ]; then
    if [ -z "$S3_ENDPOINT" ] || [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ] || [ -z "$S3_BUCKET" ]; then
        echo "Error: S3 configuration is incomplete. Please set all required environment variables."
        exit 1
    fi
    
    # Create crontab file with the schedule from environment variable
    echo "${BACKUP_SCHEDULE} /usr/local/bin/backup.sh" > /etc/crontab
    
    echo "Starting backup cron service..."
    supercronic /etc/crontab &
fi

# Delegate to the original entrypoint script with our generated config
exec /usr/local/bin/docker-entrypoint.sh valkey-server "$CONFIG_FILE"