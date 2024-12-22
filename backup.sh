#!/bin/bash

# Set environment variables
if [ -z "$S3_BUCKET" ]; then
  echo "Error: S3_BUCKET environment variable is not set"
  exit 1
fi
if [ -z "$S3_ENDPOINT" ]; then
  echo "Error: S3_ENDPOINT environment variable is not set"
  exit 1
fi
if [ -z "$S3_ACCESS_KEY" ]; then
  echo "Error: S3_ACCESS_KEY environment variable is not set"
  exit 1
fi
if [ -z "$S3_SECRET_KEY" ]; then
  echo "Error: S3_SECRET_KEY environment variable is not set"
  exit 1
fi
if [ -z "$REDIS_DATA_DIR" ]; then
  echo "Error: REDIS_DATA_DIR environment variable is not set"
  exit 1
fi
if [ -z "$BACKUP_RETENTION_DAYS" ]; then
  echo "Error: BACKUP_RETENTION_DAYS environment variable is not set"
  exit 1
fi
if [ -z "$BACKUP_ROTATION_DAYS" ]; then
  echo "Error: BACKUP_ROTATION_DAYS environment variable is not set"
  exit 1
fi
if [ -z "$ARCHIVE_RETENTION_DAYS" ]; then
  echo "Error: ARCHIVE_RETENTION_DAYS environment variable is not set"
  exit 1
fi

# Define functions
backup_data() {
  timestamp=$(date +%Y%m%d_%H%M%S)
  echo "Creating backup to S3: ${timestamp}"
  if ! redis-cli SAVE; then
    echo "Error: Failed to save Redis data"
    return 1
  fi
  if ! mc cp ${REDIS_DATA_DIR}/dump.rdb "${S3_BUCKET}/${timestamp}/dump.rdb"; then
    echo "Error: Failed to upload backup to S3"
    return 1
  fi
  
  # Validate the uploaded backup
  if ! mc ls "${S3_BUCKET}/${timestamp}/dump.rdb"; then
    echo "Error: Failed to validate uploaded backup"
    return 1
  fi
  
  # Clean up old backups
  echo "Cleaning up old backups..."
  if ! mc ls "${S3_BUCKET}/" | sort -r | \
      awk -v retention="$BACKUP_RETENTION_DAYS" 'NR > retention {print $NF}' | \
      while read -r old_backup; do
          mc rm -r --force "${S3_BUCKET}/${old_backup}"
      done; then
    echo "Error: Failed to clean up old backups"
    return 1
  fi
  
  # Rotate backups
  echo "Rotating backups..."
  if ! mc ls "${S3_BUCKET}/" | sort -r | \
      awk -v rotation="$BACKUP_ROTATION_DAYS" 'NR > rotation {print $NF}' | \
      while read -r old_backup; do
          mc mv "${S3_BUCKET}/${old_backup}" "${S3_BUCKET}/archived/${old_backup}"
      done; then
    echo "Error: Failed to rotate backups"
    return 1
  fi
  
  # Clean up old archives
  echo "Cleaning up old archives..."
  if ! mc ls "${S3_BUCKET}/archived/" | sort -r | \
      awk -v retention="$ARCHIVE_RETENTION_DAYS" 'NR > retention {print $NF}' | \
      while read -r old_archive; do
          mc rm -r --force "${S3_BUCKET}/archived/${old_archive}"
      done; then
    echo "Error: Failed to clean up old archives"
    return 1
  fi
  echo "Backup completed successfully"
}

restore_data() {
  # Download latest backup from S3
  latest_backup=$(mc ls "${S3_BUCKET}/" | sort -r | head -n 1 | awk '{print $NF}')
  echo "Restoring data from S3: ${latest_backup}"
  if ! mc cp "${S3_BUCKET}/${latest_backup}/dump.rdb" ${REDIS_DATA_DIR}/; then
    echo "Error: Failed to download backup from S3"
    return 1
  fi
  
  # Validate the downloaded backup
  if [ ! -f ${REDIS_DATA_DIR}/dump.rdb ]; then
    echo "Error: Failed to validate downloaded backup"
    return 1
  fi
  
  # Restore data to Redis
  if ! redis-cli LOAD; then
    echo "Error: Failed to load Redis data"
    return 1
  fi
  
  # Validate the restored data
  if redis-cli CHECK | grep -q "error"; then
    echo "Error: Failed to validate restored data"
    return 1
  fi
  echo "Restore completed successfully"
}

test_restore() {
  # Create a temporary Redis instance
  echo "Creating temporary Redis instance..."
  redis-server --port 6380 --dbfilename test-redis.rdb &>/dev/null &
  local redis_pid=$!
  
  # Restore the latest backup to the temporary Redis instance
  echo "Restoring latest backup to temporary Redis instance..."
  if ! mc cp "${S3_BUCKET}/$(mc ls "${S3_BUCKET}/" | sort -r | head -n 1 | awk '{print $NF}')/dump.rdb" /tmp/test-redis.rdb; then
    echo "Error: Failed to download backup from S3"
    kill $redis_pid
    return 1
  fi
  if ! redis-cli -p 6380 RESTORE /tmp/test-redis.rdb; then
    echo "Error: Failed to restore backup to temporary Redis instance"
    kill $redis_pid
    return 1
  fi
  
  # Validate the restored data
  echo "Validating restored data..."
  if redis-cli -p 6380 CHECK | grep -q "error"; then
    echo "Error: Failed to validate restored data"
    kill $redis_pid
    return 1
  fi
  
  # Clean up
  echo "Cleaning up..."
  if ! redis-cli -p 6380 SHUTDOWN; then
    echo "Error: Failed to shut down temporary Redis instance"
    kill $redis_pid
    return 1
  fi
  if ! rm /tmp/test-redis.rdb; then
    echo "Error: Failed to remove temporary Redis database file"
    return 1
  fi
  echo "Restore test completed successfully"
}

# Call functions based on command-line arguments
case ${1} in
  backup)
    if ! backup_data; then
      echo "Error: Backup failed"
      exit 1
    fi
    ;;
  restore)
    if ! restore_data; then
      echo "Error: Restore failed"
      exit 1
    fi
    ;;
  test-restore)
    if ! test_restore; then
      echo "Error: Restore test failed"
      exit 1
    fi
    ;;
  *)
    echo "Invalid command"
    exit 1
    ;;
esac
