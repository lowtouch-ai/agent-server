#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Fetch secrets from Vault if needed
if env | grep -q "VAULT:"; then
  echo "Fetching secrets from Vault..."
  c=1
  mc=180
  while ! curl -k -o /dev/null -s -w "%{http_code}" "$VAULT_ADDR/v1/sys/health" | grep -q "200"; do
    echo "waiting for $VAULT_ADDR..."
    sleep 1
    c=$((c + 1))
    if [ "$c" -gt "$mc" ]; then
      echo "FATAL: Vault timeout... exiting"
      exit 1
    fi
  done
  VAULT_GET_ADDR=$(echo "$VAULT_ADDR" | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
  source <(curl -s "$VAULT_GET_ADDR/get_secret.sh")
fi

# Environment variables
REPLICATION="${REPLICATION:-0}"
AUTH_ENABLE="${AUTH_ENABLE:-0}"
REPLICA_SET_NAME="${REPLICA_SET_NAME:-rs0}"
DB_USER_ADMIN="${DB_USER_ADMIN:-admin}"
DB_USER_ADMIN_PASSWORD="${DB_USER_ADMIN_PASSWORD:-}"
AUTH_KEY="${AUTH_KEY:-}"
HOSTNAME_FULL=$(hostname)

# ----------------------------------------------------
# --- AUTOMATIC KUBERNETES FQDN DEDUCTION ---
# ----------------------------------------------------
echo "Attempting to auto-deduce Kubernetes FQDN details..."
KUBE_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace 2>/dev/null || echo "")
SHORT_INDEX=$(echo "$HOSTNAME_FULL" | awk -F'-' '{print $NF}' | grep -o '[0-9]\+$' || echo 0)
N=${SHORT_INDEX:-0}
KUBE_POD_PREFIX=$(echo "$HOSTNAME_FULL" | sed "s/-$N$//")
KUBE_SERVICE_NAME="${KUBE_POD_PREFIX}"

if [ -z "$KUBE_NAMESPACE" ] || [ -z "$KUBE_SERVICE_NAME" ] || [ -z "$KUBE_POD_PREFIX" ]; then
    echo "WARNING: Could not automatically deduce all Kubernetes FQDN details. Using fallback names."
    KUBE_NAMESPACE=""
    KUBE_SERVICE_NAME=""
    KUBE_POD_PREFIX=""
else
    echo "Auto-deduction successful."
    echo " KUBE_NAMESPACE: $KUBE_NAMESPACE"
    echo " KUBE_SERVICE_NAME: $KUBE_SERVICE_NAME"
    echo " KUBE_POD_PREFIX: $KUBE_POD_PREFIX"
fi

MASTER_ENABLE="${MASTER_ENABLE:-no}"
APPZ_APP_NAME="${APPZ_APP_NAME:-}"
TAIL_LOG="${TAIL_LOG:-1}"

# ----------------------------------------------------
# --- HELPER FUNCTIONS ---
# ----------------------------------------------------
get_replica_host() {
    local index=$1
    if [ -n "$KUBE_NAMESPACE" ] && [ -n "$KUBE_SERVICE_NAME" ] && [ -n "$KUBE_POD_PREFIX" ]; then
        echo "${KUBE_POD_PREFIX}-${index}.${KUBE_SERVICE_NAME}.${KUBE_NAMESPACE}.svc.cluster.local:27017"
    else
        echo "mongo-${index}:27017"
    fi
}

mongo_status_check() {
  local maxcounter=60
  local counter=1
  while ! mongosh --host localhost --port 27017 --quiet --eval "db.runCommand({ ping: 1 }).ok" >/dev/null 2>&1; do
    sleep 1
    counter=$((counter + 1))
    if [ "$counter" -gt "$maxcounter" ]; then
      echo "ERROR: MongoDB failed to start"
      tail -n 30 /appz/log/mongodb.log 2>/dev/null || tail -n 30 /appz/log/mongod.log 2>/dev/null || true
      exit 1
    fi
  done
  echo "MongoDB is up"
}

wait_for_node() {
  local host=$1
  local max_attempts=20
  local attempt=1
  while ! mongosh --host "$host" --quiet --eval "db.runCommand({ ping: 1 }).ok" >/dev/null 2>&1; do
    sleep 1
    attempt=$((attempt + 1))
    if [ "$attempt" -gt "$max_attempts" ]; then
      echo "ERROR: Cannot reach $host"
      return 1
    fi
  done
  echo "$host reachable"
  return 0
}

kill_mongodb_processes() {
  echo "Checking for existing MongoDB processes..."
  PIDS_MONGO=$(ps aux | awk '/mongod/ && !/grep/ && !/scripts/ {print $2}')
  if [ -n "$PIDS_MONGO" ]; then
    echo "Stopping existing MongoDB processes..."
    for PID in $PIDS_MONGO; do
      echo "Killing MongoDB process: $PID"
      kill "$PID" 2>/dev/null || true
      local wait_count=0
      while ps -p "$PID" > /dev/null 2>&1 && [ $wait_count -lt 5 ]; do
        sleep 1
        wait_count=$((wait_count + 1))
      done
      if ps -p "$PID" > /dev/null 2>&1; then
        echo "Process $PID did not terminate gracefully, sending SIGKILL..."
        kill -9 "$PID" 2>/dev/null || true
      fi
      echo "Process $PID has terminated."
    done
  else
    echo "No MongoDB processes found."
  fi
}

shutdown_mongodb() {
  echo "Shutting down MongoDB instance..."
  mongosh --host localhost --port 27017 --quiet admin --eval "db.shutdownServer()" >/dev/null 2>&1 || true
  sleep 2
  kill_mongodb_processes
}

create_admin_user() {
  local dbpath="$1"
  if [ -z "$DB_USER_ADMIN" ] || [ -z "$DB_USER_ADMIN_PASSWORD" ]; then
    echo "ERROR: DB_USER_ADMIN or DB_USER_ADMIN_PASSWORD not set!"
    exit 1
  fi
  # Start temporarily in background
  mongod --dbpath="$dbpath" --bind_ip_all --logpath /appz/log/start.log &
  mongo_status_check
  echo "MongoDB started without authentication for user creation."
  sleep 2
  JS_PWD=$(python3 -c "import json; print(json.dumps('$DB_USER_ADMIN_PASSWORD'))")
  mongosh --quiet admin --eval "
    try {
      db.dropUser('$DB_USER_ADMIN');
      print('Dropped existing user $DB_USER_ADMIN');
    } catch (e) {
      if (e.codeName != 'UserNotFound') {
        throw e;
      }
    }
    db.createUser({
      user: '$DB_USER_ADMIN',
      pwd: $JS_PWD,
      roles: [{ role: 'root', db: 'admin' }]
    });
    print('User $DB_USER_ADMIN created successfully');
  " >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create admin user"
    tail -20 /appz/log/start.log
    exit 1
  fi
  echo "Admin user created"
}

start_mongodb_with_auth() {
  local dbpath="$1"
  local config="$2"
  echo "Starting MongoDB with authentication enabled"
  if [ -n "$config" ] && [ -f "$config" ]; then
    su - mongodb -c "exec mongod --auth --dbpath=$dbpath --config $config --logpath=/appz/log/mongod.log" 2>/dev/null || \
      exec mongod --auth --dbpath="$dbpath" --config "$config" --logpath=/appz/log/mongod.log
  else
    su - mongodb -c "exec mongod --auth --dbpath=$dbpath --bind_ip_all --logpath=/appz/log/mongod.log" 2>/dev/null || \
      exec mongod --auth --dbpath="$dbpath" --bind_ip_all --logpath=/appz/log/mongod.log
  fi
}

# ----------------------------------------------------
# --- MAIN LOGIC ---
# ----------------------------------------------------
kill_mongodb_processes

# Condition 1: Standalone without auth
if [ "$REPLICATION" -eq 0 ] && [ "$AUTH_ENABLE" -eq 0 ]; then
  echo "Starting standalone MongoDB without authentication"
  exec mongod --dbpath=/appz/data/ --bind_ip_all --logpath=/appz/log/mongod.log

# Condition 2: Standalone with auth
elif [ "$REPLICATION" -eq 0 ] && [ "$AUTH_ENABLE" -eq 1 ]; then
  echo "Starting standalone MongoDB with authentication"
  create_admin_user "/appz/data/"
  shutdown_mongodb
  start_mongodb_with_auth "/appz/data/" ""
  if [ "$TAIL_LOG" -eq 1 ]; then
    exec tail -f /appz/log/mongod.log
  else
    exec mongod --auth --dbpath=/appz/data/ --bind_ip_all --logpath=/appz/log/mongod.log
  fi

# Condition 3: Replica Set WITHOUT auth
elif [ "$REPLICATION" -ge 1 ] && [ "$AUTH_ENABLE" -eq 0 ]; then
  if [ -z "$KUBE_NAMESPACE" ] || [ -z "$KUBE_SERVICE_NAME" ] || [ -z "$KUBE_POD_PREFIX" ]; then
    echo "FATAL ERROR: Replica Set required but FQDN details could not be determined."
    exit 1
  fi
  echo "Starting MongoDB Replica Set WITHOUT authentication using calculated FQDNs"
  DBPATH="/appz/data/tmp$N"
  mkdir -p "$DBPATH" /appz/log
  chown -R mongodb:mongodb "$DBPATH" /appz/log 2>/dev/null || true
  chmod -R 700 "$DBPATH" /appz/log
  rm -f "$DBPATH/mongod.lock"

  CONFIG_FILE="/etc/mongod.conf"
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file $CONFIG_FILE not found"
    exit 1
  fi

  CLEAN_CONFIG_FILE="/tmp/mongod-clean.conf"
  grep -v "security:" "$CONFIG_FILE" | grep -v "authorization:" | grep -v "keyFile:" | sed "s|dbPath:.*|dbPath: $DBPATH|" > "$CLEAN_CONFIG_FILE"
  echo "Creating unauthenticated config at $CLEAN_CONFIG_FILE"

  REJOINING=false
  if [ -f "$DBPATH/WiredTiger" ] || [ -f "$DBPATH/storage.bson" ]; then
    echo "Detected existing database - rejoining mode"
    REJOINING=true
  fi

  if [ "$N" -eq 0 ]; then
    if [ "$REJOINING" = true ]; then
      echo "PRIMARY REJOIN: Restarting and syncing..."
      su - mongodb -c "exec mongod --config $CLEAN_CONFIG_FILE --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        exec mongod --config "$CLEAN_CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log
    else
      echo "PRIMARY: Initializing replica set..."
      su - mongodb -c "mongod --config $CLEAN_CONFIG_FILE --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        mongod --config "$CLEAN_CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log &
      sleep 3
      mongo_status_check
      for i in $(seq 0 $((REPLICATION - 1))); do
        HOST=$(get_replica_host "$i")
        wait_for_node "$HOST" || echo "Warning: $HOST not reachable"
      done
      MEMBERS_JS=""
      for i in $(seq 0 $((REPLICATION - 1))); do
        HOST=$(get_replica_host "$i")
        PRIORITY=$(( i == 0 ? 2 : 1 ))
        MEMBERS_JS="${MEMBERS_JS}{ _id: $i, host: '$HOST', priority: $PRIORITY },"
      done
      MEMBERS_JS="${MEMBERS_JS%,}"
      mongosh --host localhost --port 27017 --quiet --eval "rs.initiate({ _id: '$REPLICA_SET_NAME', members: [$MEMBERS_JS] })" >/dev/null 2>&1
      echo "Replica set initialized"
      for i in {1..30}; do
        STATUS=$(mongosh --host localhost --port 27017 --quiet --eval "rs.status().myState" 2>/dev/null || echo 0)
        [ "$STATUS" = "1" ] && break
        sleep 1
      done
      if [ "$STATUS" != "1" ]; then
        echo "ERROR: Failed to become PRIMARY"
        exit 1
      fi
      echo "Node is PRIMARY"
      # Now replace shell with mongod
      exec mongod --config "$CLEAN_CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log
    fi
  else
    if [ "$REJOINING" = true ]; then
      echo "SECONDARY $N REJOIN: Restarting and syncing..."
      su - mongodb -c "exec mongod --config $CLEAN_CONFIG_FILE --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        exec mongod --config "$CLEAN_CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log
    else
      echo "SECONDARY $N: Joining replica set..."
      su - mongodb -c "mongod --config $CLEAN_CONFIG_FILE --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        mongod --config "$CLEAN_CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log &
      sleep 3
      mongo_status_check
      for i in {1..60}; do
        RS_STATUS=$(mongosh --host localhost --port 27017 --quiet --eval "rs.status().ok" 2>/dev/null || echo 0)
        if [ "$RS_STATUS" = "1" ]; then
          echo "Joined replica set"
          break
        fi
        sleep 2
      done
      if [ "$RS_STATUS" != "1" ]; then
        echo "ERROR: Failed to join replica set"
        exit 1
      fi
      tee /etc/mongorc.js <<EOF >/dev/null
rs.secondaryOk()
EOF
      # Now replace shell with mongod
      exec mongod --config "$CLEAN_CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log
    fi
  fi

  # Final exec for non-rejoin paths
  if [ "$TAIL_LOG" -eq 1 ]; then
    exec tail -f /appz/log/mongodb.log
  else
    exec mongod --dbpath="$DBPATH" --config "$CLEAN_CONFIG_FILE" --logpath=/appz/log/mongodb.log
  fi

# Condition 4: Replica Set WITH auth
elif [ "$REPLICATION" -ge 1 ] && [ "$AUTH_ENABLE" -eq 1 ]; then
  if [ -z "$KUBE_NAMESPACE" ] || [ -z "$KUBE_SERVICE_NAME" ] || [ -z "$KUBE_POD_PREFIX" ]; then
    echo "FATAL ERROR: Replica Set required but FQDN details could not be determined."
    exit 1
  fi
  echo "Starting MongoDB Replica Set with authentication using calculated FQDNs"
  mkdir -p /appz/keys
  if [ -z "$AUTH_KEY" ]; then
    echo "ERROR: AUTH_KEY not set for replica set"
    exit 1
  fi
  if [ -f "$AUTH_KEY" ]; then
    cat "$AUTH_KEY" > /appz/keys/key.txt
  else
    echo "$AUTH_KEY" > /appz/keys/key.txt
  fi
  chmod 400 /appz/keys/key.txt
  chown mongodb:mongodb /appz/keys/key.txt 2>/dev/null || true

  DBPATH="/appz/data/tmp$N"
  mkdir -p "$DBPATH" /appz/log
  chown -R mongodb:mongodb "$DBPATH" /appz/log 2>/dev/null || true
  chmod -R 700 "$DBPATH" /appz/log
  rm -f "$DBPATH/mongod.lock"

  CONFIG_FILE="/etc/mongod.conf"
  CONFIG_NOAUTH="/tmp/mongod-noauth.conf"
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file $CONFIG_FILE not found"
    exit 1
  fi
  grep -v "security:" "$CONFIG_FILE" | grep -v "authorization:" | grep -v "keyFile:" | sed "s|dbPath:.*|dbPath: $DBPATH|" > "$CONFIG_NOAUTH"

  REJOINING=false
  if [ -f "$DBPATH/WiredTiger" ] || [ -f "$DBPATH/storage.bson" ]; then
    echo "Detected existing database - rejoining mode"
    REJOINING=true
  fi

  if [ "$N" -eq 0 ]; then
    if [ "$REJOINING" = true ]; then
      echo "PRIMARY REJOIN: Restarting and syncing..."
      su - mongodb -c "exec mongod --config $CONFIG_FILE --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        exec mongod --config "$CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log
    else
      echo "PRIMARY: Initializing replica set..."
      create_admin_user "$DBPATH"
      shutdown_mongodb
      su - mongodb -c "mongod --config $CONFIG_NOAUTH --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        mongod --config "$CONFIG_NOAUTH" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log &
      sleep 3
      mongo_status_check
      for i in $(seq 0 $((REPLICATION - 1))); do
        HOST=$(get_replica_host "$i")
        wait_for_node "$HOST" || echo "Warning: $HOST not reachable"
      done
      MEMBERS_JS=""
      for i in $(seq 0 $((REPLICATION - 1))); do
        HOST=$(get_replica_host "$i")
        PRIORITY=$(( i == 0 ? 2 : 1 ))
        MEMBERS_JS="${MEMBERS_JS}{ _id: $i, host: '$HOST', priority: $PRIORITY },"
      done
      MEMBERS_JS="${MEMBERS_JS%,}"
      mongosh --host localhost --port 27017 --quiet --eval "rs.initiate({ _id: '$REPLICA_SET_NAME', members: [$MEMBERS_JS] })" >/dev/null 2>&1
      echo "Replica set initialized"
      for i in {1..30}; do
        STATUS=$(mongosh --host localhost --port 27017 --quiet --eval "rs.status().myState" 2>/dev/null || echo 0)
        [ "$STATUS" = "1" ] && break
        sleep 1
      done
      if [ "$STATUS" != "1" ]; then
        echo "ERROR: Failed to become PRIMARY"
        exit 1
      fi
      echo "Node is PRIMARY"
      JS_PWD=$(python3 -c "import json; print(json.dumps('$DB_USER_ADMIN_PASSWORD'))")
      mongosh --host localhost --port 27017 --quiet admin --eval "
        if (db.getUser('$DB_USER_ADMIN') == null) {
          db.createUser({ user: '$DB_USER_ADMIN', pwd: $JS_PWD, roles: [{ role: 'root', db: 'admin' }] });
        }
      " >/dev/null 2>&1
      echo "Admin user created in replica set"
      sleep 5
      for i in $(seq 1 $((REPLICATION - 1))); do
        HOST=$(get_replica_host "$i")
        for j in {1..10}; do
          USER_COUNT=$(mongosh --host "$HOST" -u "$DB_USER_ADMIN" -p "$DB_USER_ADMIN_PASSWORD" --authenticationDatabase admin --quiet --eval "db.getSiblingDB('admin').getUsers().length" 2>/dev/null | tail -1 || echo 0)
          [ "$USER_COUNT" -ge 1 ] && break
          sleep 1
        done
      done
      echo "User replicated"
      shutdown_mongodb
      echo "Starting with authentication..."
      su - mongodb -c "exec mongod --config $CONFIG_FILE --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        exec mongod --config "$CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log
    fi
  else
    if [ "$REJOINING" = true ]; then
      echo "SECONDARY $N REJOIN: Restarting and syncing..."
      su - mongodb -c "exec mongod --config $CONFIG_FILE --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        exec mongod --config "$CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log
    else
      echo "SECONDARY $N: Joining replica set..."
      su - mongodb -c "mongod --config $CONFIG_NOAUTH --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        mongod --config "$CONFIG_NOAUTH" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log &
      sleep 3
      mongo_status_check
      for i in {1..60}; do
        RS_STATUS=$(mongosh --host localhost --port 27017 --quiet --eval "rs.status().ok" 2>/dev/null || echo 0)
        if [ "$RS_STATUS" = "1" ]; then
          echo "Joined replica set"
          break
        fi
        sleep 2
      done
      if [ "$RS_STATUS" != "1" ]; then
        echo "ERROR: Failed to join replica set"
        exit 1
      fi
      tee /etc/mongorc.js <<EOF >/dev/null
rs.secondaryOk()
EOF
      shutdown_mongodb
      echo "Starting with authentication..."
      su - mongodb -c "exec mongod --config $CONFIG_FILE --dbpath=$DBPATH --logpath=/appz/log/mongodb.log" 2>/dev/null || \
        exec mongod --config "$CONFIG_FILE" --dbpath="$DBPATH" --logpath=/appz/log/mongodb.log
    fi
  fi

  if [ -n "$DB_USER_ADMIN" ] && [ -n "$DB_USER_ADMIN_PASSWORD" ]; then
    AUTH_TEST=$(mongosh --host localhost --port 27017 -u "$DB_USER_ADMIN" -p "$DB_USER_ADMIN_PASSWORD" --authenticationDatabase admin --quiet --eval "db.runCommand({ connectionStatus: 1 }).ok" 2>/dev/null || echo 0)
    if [ "$AUTH_TEST" = "1" ]; then
      echo "Authentication working"
    else
      echo "WARNING: Authentication test failed"
    fi
  fi

  FINAL_STATE=$(mongosh --host localhost --port 27017 -u "$DB_USER_ADMIN" -p "$DB_USER_ADMIN_PASSWORD" --authenticationDatabase admin --quiet --eval "rs.status().members.find(m => m.self).stateStr" 2>/dev/null || echo "UNKNOWN")
  echo "MongoDB Node $N ready! State: $FINAL_STATE"
  if [ "$TAIL_LOG" -eq 1 ]; then
    exec tail -f /appz/log/mongodb.log
  else
    exec mongod --dbpath="$DBPATH" --config "$CONFIG_FILE" --logpath=/appz/log/mongodb.log
  fi

else
  echo "ERROR: Invalid configuration - REPLICATION=$REPLICATION, AUTH_ENABLE=$AUTH_ENABLE"
  echo "Supported configurations:"
  echo " - REPLICATION=0, AUTH_ENABLE=0"
  echo " - REPLICATION=0, AUTH_ENABLE=1"
  echo " - REPLICATION>=1, AUTH_ENABLE=0"
  echo " - REPLICATION>=1, AUTH_ENABLE=1"
  exit 1
fi
