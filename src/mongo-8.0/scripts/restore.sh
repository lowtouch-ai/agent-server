#!/bin/bash
set -euo pipefail

# --- 1. VAULT SECRETS FETCH ---
if env | grep -q "VAULT:"; then
    c=1
    mc=180
    while ! curl -k -s -w "%{http_code}" "$VAULT_ADDR/v1/sys/health" -o /dev/null | grep -q "200"; do
        echo "waiting for $VAULT_ADDR..."
        sleep 1
        ((c++))
        if [ "$c" -gt "$mc" ]; then
            echo "FATAL: vault timeout... exiting"
            exit 1
        fi
    done
    VAULT_GET_ADDR=$(echo "$VAULT_ADDR" | awk -F: '{print $1":"$2}' | sed 's/https/http/g')
    source <(curl -s "$VAULT_GET_ADDR/get_secret.sh")
fi

# --- 2. VALIDATE INPUT ---
if [ $# -ne 1 ]; then
    echo "Usage: $0 <backup_file>"
    echo "  Encrypted:  mydb_2025-10-31T12:00:00Z.gz.enc"
    echo "  Plain gzip: mydb_2025-10-31T12:00:00Z.gz"
    echo ""
    echo "Available files in /appz/backup:"
    ls -1 /appz/backup/*.gz* 2>/dev/null | sed 's|.*/|  |' || echo "  (none)"
    exit 1
fi

FILE="$1"
INPUT="/appz/backup/$FILE"

if [ ! -f "$INPUT" ]; then
    echo "ERROR: File not found: $INPUT"
    echo "Check /appz/backup/ directory"
    exit 1
fi

# --- 3. DETERMINE TYPE & DECRYPT IF NEEDED ---
if [[ "$FILE" = *.enc ]]; then
    DECRYPTED="/appz/backup/${FILE%.enc}"
    echo "Encrypted backup detected. Decrypting..."
    openssl enc -d -aes-256-cbc -md sha512 -pbkdf2 -iter 100000 -salt \
        -k "$ENCRYPTION_KEY" \
        -in "$INPUT" \
        -out "$DECRYPTED" \
        || { echo "ERROR: Decryption failed. Wrong ENCRYPTION_KEY?"; exit 1; }
    ARCHIVE="$DECRYPTED"
    CLEANUP=true
else
    echo "Plain gzip backup detected. Skipping decryption."
    ARCHIVE="$INPUT"
    CLEANUP=false
fi

# --- 4. RESTORE ---
echo "Restoring from: $ARCHIVE"
mongorestore \
    --uri "mongodb://$DB_USER_ADMIN:$DB_USER_ADMIN_PASSWORD@$MONGODB_HOST:$MONGODB_PORT/?authSource=admin" \
    --gzip \
    --archive="$ARCHIVE" \
    --quiet  # Remove if you want full mongorestore output

# --- 5. CLEANUP ---
if [ "$CLEANUP" = true ]; then
    rm -f "$DECRYPTED"
    echo "Unencrypted file securely deleted."
fi

echo "Restore completed successfully."
