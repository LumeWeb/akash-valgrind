#!/bin/sh
set -e

# Configure MinIO client
mc alias set backup "${S3_ENDPOINT}" "${S3_ACCESS_KEY}" "${S3_SECRET_KEY}"

timestamp=$(date +%Y%m%d_%H%M%S)
backup_path="${BACKUP_PREFIX}/${timestamp}"

echo "Creating backup to S3: ${backup_path}"
mc cp -r /path/to/data "backup/${S3_BUCKET}/${backup_path}/"

# Clean up old backups
echo "Cleaning up old backups..."
mc ls "backup/${S3_BUCKET}/${BACKUP_PREFIX}/" | sort -r | \
    awk -v retention="$BACKUP_RETENTION_DAYS" 'NR > retention {print $NF}' | \
    while read -r old_backup; do
        mc rm -r --force "backup/${S3_BUCKET}/${BACKUP_PREFIX}/${old_backup}"
    done 