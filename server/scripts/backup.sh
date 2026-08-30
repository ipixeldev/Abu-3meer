#!/bin/sh
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backups"
DUMP_FILE="$BACKUP_DIR/abu3meer_db_$TIMESTAMP.sql.gz"
ENCRYPTED_FILE="$DUMP_FILE.enc"
UPLOADS_FILE="$BACKUP_DIR/abu3meer_uploads_$TIMESTAMP.tar.gz"
ENCRYPTED_UPLOADS_FILE="$UPLOADS_FILE.enc"

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is required}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is required}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is required}"
: "${R2_BUCKET:?R2_BUCKET is required}"
: "${BACKUP_ENCRYPTION_KEY:?BACKUP_ENCRYPTION_KEY is required}"

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting PostgreSQL logical dump..."
pg_dump -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists | gzip -9 > "$DUMP_FILE"

echo "[$(date)] Archiving persistent media uploads..."
tar -C /uploads -czf "$UPLOADS_FILE" .

echo "[$(date)] Encrypting database and media backups with AES-256..."
printf '%s' "$BACKUP_ENCRYPTION_KEY" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --symmetric --cipher-algo AES256 -o "$ENCRYPTED_FILE" "$DUMP_FILE"
printf '%s' "$BACKUP_ENCRYPTION_KEY" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --symmetric --cipher-algo AES256 -o "$ENCRYPTED_UPLOADS_FILE" "$UPLOADS_FILE"
rm -f "$DUMP_FILE" "$UPLOADS_FILE"

echo "[$(date)] Uploading encrypted backups to Cloudflare R2 bucket: $R2_BUCKET..."
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

R2_ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"

aws --endpoint-url "$R2_ENDPOINT" s3 cp "$ENCRYPTED_FILE" "s3://$R2_BUCKET/db_backups/$(basename "$ENCRYPTED_FILE")"
aws --endpoint-url "$R2_ENDPOINT" s3 cp "$ENCRYPTED_UPLOADS_FILE" "s3://$R2_BUCKET/media_backups/$(basename "$ENCRYPTED_UPLOADS_FILE")"
echo "[$(date)] Backup upload complete!"

# Clean up local temporary files older than 3 days
find "$BACKUP_DIR" -type f -name "abu3meer_db_*" -mtime +3 -delete
echo "[$(date)] Backup rotation and cleanup finished."
