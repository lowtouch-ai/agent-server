#!/bin/bash
source ../init.sh

VOLUME_PATH="/home/appz/volumes/${PROJECT}"

if [ ! -d "$VOLUME_PATH" ]; then
  echo "Error: Volume folder for project $PROJECT does not exist at $VOLUME_PATH."
  exit 1
fi

BACKUP_FILE="${VOLUME_PATH}/${PROJECT}_$(date +%Y%m%d_%H%M).tar.gz"

echo "Creating backup for project: $PROJECT at $VOLUME_PATH"
BACKUP_OUTPUT=$(sudo tar --warning=no-file-changed -czvf "$BACKUP_FILE" -C "$VOLUME_PATH" . 2>&1)

if echo "$BACKUP_OUTPUT" | grep -q "Error"; then
  echo "Backup failed due to errors!"
  echo "$BACKUP_OUTPUT"
  exit 1
else
  echo "$BACKUP_OUTPUT"
  echo "Backup completed successfully! File: $BACKUP_FILE"
fi

