#!/bin/bash

source ../init.sh

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Error: Please provide both the timestamp and the folder where the data should be restored."
  echo "Usage: ./restore.sh <timestamp> <restore-folder>"
  echo "Eg: ./restore.sh 20240925_0942 /home/appz/volumes/"
  exit 1
fi

TIMESTAMP=$1
RESTORE_PATH=$2

VOLUME_PATH="/home/appz/volumes/${PROJECT}"
BACKUP_FILE="${VOLUME_PATH}/${PROJECT}_${TIMESTAMP}.tar.gz"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: Backup file ${BACKUP_FILE} does not exist."
  exit 1
fi

if [ ! -d "$RESTORE_PATH" ]; then
  sudo mkdir -p "$RESTORE_PATH"
fi

echo "Restoring backup from: $BACKUP_FILE to $RESTORE_PATH"
sudo tar -xzvf "$BACKUP_FILE" -C "$RESTORE_PATH"

if [ $? -eq 0 ]; then
  echo "Restore completed successfully! Files are available at $RESTORE_PATH"
else
  echo "Restore failed!"
  exit 1
fi

