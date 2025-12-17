
#!/bin/bash

set -euo pipefail

# --- 1. VAULT/ENVIRONMENT SETUP ---
if env | grep "VAULT:" > /dev/null 2>&1
then
    c=1
    mc=180
    # FIX: Corrected syntax for 'while ! command; do' and pipe
    while ! curl -k -o /dev/null -s -w "%{http_code}" -k "$VAULT_ADDR/v1/sys/health" 2>/dev/null | grep "200" >/dev/null; do
        echo "waiting for $VAULT_ADDR..."
        sleep 1
        # FIX: Used standard bash increment
        c=$((c + 1))
        if [ "$c" -gt "$mc" ]; then
            echo "FATAL: vault timeout... exiting"
            exit 1
        fi
    done

    VAULT_GET_ADDR=$(echo "$VAULT_ADDR"|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
    source <(curl -s "$VAULT_GET_ADDR/get_secret.sh")
fi

# Environment variables
REPLICATION="${REPLICATION:-0}"
AUTH_ENABLE="${AUTH_ENABLE:-0}"
DB_USER_ADMIN="${DB_USER_ADMIN:-admin}"
DB_USER_ADMIN_PASSWORD="${DB_USER_ADMIN_PASSWORD:-}"
MONGODB_HOST="${MONGODB_HOST:-127.0.0.1}"
MONGODB_PORT="${MONGODB_PORT:-27017}"
REPLICA_SET_NAME="${REPLICA_SET_NAME:-rs0}"

echo "Starting MongoDB Exporter - REPLICATION=$REPLICATION, AUTH_ENABLE=$AUTH_ENABLE"

# --- 2. WAIT FUNCTION ---
# Wait for MongoDB to be ready
wait_for_mongodb() {
    local maxcounter=60
    local counter=1

    echo "Waiting for MongoDB to be ready..."
    while true; do
        if [ "$AUTH_ENABLE" -eq 1 ]; then
            # Check with authentication
            if mongosh --host "$MONGODB_HOST" --port "$MONGODB_PORT" \
                -u "$DB_USER_ADMIN" -p "$DB_USER_ADMIN_PASSWORD" \
                --authenticationDatabase admin --quiet \
                --eval "db.runCommand({ ping: 1 }).ok" >/dev/null 2>&1; then
                echo "✓ MongoDB is ready (authenticated)"
                return 0
            fi
        else
            # Check without authentication
            if mongosh --host "$MONGODB_HOST" --port "$MONGODB_PORT" --quiet \
                --eval "db.runCommand({ ping: 1 }).ok" >/dev/null 2>&1; then
                echo "✓ MongoDB is ready (no auth)"
                return 0
            fi
        fi

        sleep 1
        counter=$((counter + 1))
        if [ "$counter" -gt "$maxcounter" ]; then
            echo "⚠️  WARNING: MongoDB not ready, starting exporter anyway..."
            return 1
        fi
    done
}

# Wait for MongoDB to be available
wait_for_mongodb || true

# --- 3. URI CONSTRUCTION ---

if [ "$AUTH_ENABLE" -eq 1 ]; then
    # URL-encode the password
    ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote_plus('$DB_USER_ADMIN_PASSWORD'))")

    AUTH_CREDENTIALS="${DB_USER_ADMIN}:${ENCODED_PASSWORD}@"
    AUTH_PARAMS="authSource=admin"
else
    AUTH_CREDENTIALS=""
    AUTH_PARAMS=""
fi

if [ "$REPLICATION" -gt 1 ]; then
    # REPLICA SET MODE

    if [ -n "$AUTH_PARAMS" ]; then
        RS_PARAMS="&replicaSet=${REPLICA_SET_NAME}"
    else
        RS_PARAMS="replicaSet=${REPLICA_SET_NAME}"
    fi

    if [ -n "$AUTH_PARAMS" ]; then
        MONGO_URI="mongodb://${AUTH_CREDENTIALS}${MONGODB_HOST}:${MONGODB_PORT}/?${AUTH_PARAMS}${RS_PARAMS}"
    else
        MONGO_URI="mongodb://${AUTH_CREDENTIALS}${MONGODB_HOST}:${MONGODB_PORT}/?${RS_PARAMS}"
    fi

    echo "Connecting to MongoDB Replica Set: $MONGODB_HOST:$MONGODB_PORT (Replica Set: $REPLICA_SET_NAME)"
else
    # STANDALONE MODE
    if [ -n "$AUTH_PARAMS" ]; then
        MONGO_URI="mongodb://${AUTH_CREDENTIALS}${MONGODB_HOST}:${MONGODB_PORT}/?${AUTH_PARAMS}"
        echo "Connecting to MongoDB Standalone: $MONGODB_HOST:$MONGODB_PORT (with auth)"
    else
        MONGO_URI="mongodb://${MONGODB_HOST}:${MONGODB_PORT}/"
        echo "Connecting to MongoDB Standalone: $MONGODB_HOST:$MONGODB_PORT (no auth)"
    fi
fi

echo "MongoDB URI configured (credentials hidden)"

# --- 4. EXPORTER EXECUTION ---
echo "Starting mongodb_exporter..."

# Start the exporter with the constructed URI
exec mongodb_exporter --mongodb.uri="$MONGO_URI" \
    --web.listen-address=":9216" \
    --log.level=info \
    --collect-all \
    --compatible-mode

