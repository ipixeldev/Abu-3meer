#!/bin/sh
set -e

if [ -z "$1" ]; then
  echo "Usage: ./restore.sh <path_to_backup_file>"
  exit 1
fi

BACKUP_FILE="$1"
RESTORE_SQL="/tmp/restore_temp.sql"

echo "Preparing restoration from: $BACKUP_FILE"

if echo "$BACKUP_FILE" | grep -q "\.enc$"; then
  echo "Decrypting file..."
  read -s -p "Enter GPG Passphrase: " PASSPHRASE
  echo ""
  gpg --batch --yes --passphrase "$PASSPHRASE" --decrypt "$BACKUP_FILE" | gunzip > "$RESTORE_SQL"
elif echo "$BACKUP_FILE" | grep -q "\.gz$"; then
  gunzip -c "$BACKUP_FILE" > "$RESTORE_SQL"
else
  cp "$BACKUP_FILE" "$RESTORE_SQL"
fi

echo "Applying restore to database $POSTGRES_DB..."
psql -h "${POSTGRES_HOST:-localhost}" -U "${POSTGRES_USER:-abu3meer_admin}" -d "${POSTGRES_DB:-abu3meer_prod}" -f "$RESTORE_SQL"

rm -f "$RESTORE_SQL"
echo "Database restoration completed successfully!"
