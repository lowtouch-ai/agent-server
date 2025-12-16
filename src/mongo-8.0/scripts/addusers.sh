#!/bin/bash
set -euo pipefail

# --- 1. ENVIRONMENT/VAULT SETUP ---
YAML_FILE=/appz/scripts/mongo_contents/setup.yaml
if env | grep "VAULT:" >/dev/null 2>&1; then
    c=1
    mc=180
    while ! curl -k -o /dev/null -s -w "%{http_code}" "$VAULT_ADDR/v1/sys/health" 2>/dev/null | grep "200" >/dev/null; do
        echo "waiting for $VAULT_ADDR..."
        sleep 1
        c=$((c + 1))
        if [ "$c" -gt "$mc" ]; then
            echo "FATAL: vault timeout... exiting"
            exit 1
        fi
    done
    VAULT_GET_ADDR=$(echo "$VAULT_ADDR" | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
    source <(curl -s "$VAULT_GET_ADDR/get_secret.sh")
fi

REPLICATION="${REPLICATION:-0}"
AUTH_ENABLE="${AUTH_ENABLE:-0}"
DB_USER_ADMIN="${DB_USER_ADMIN:-admin}"
DB_USER_ADMIN_PASSWORD="${DB_USER_ADMIN_PASSWORD:-}"
HOSTNAME_FULL=$(hostname)
echo "Starting addusers script - REPLICATION=$REPLICATION, AUTH_ENABLE=$AUTH_ENABLE"

# --- 2. HELPER FUNCTIONS ---

# Wait for local MongoDB to respond
wait_for_mongo() {
    local maxcounter=90
    local counter=1
    echo "Waiting for MongoDB to be ready..."
    while ! mongosh --quiet --eval "db.runCommand({ ping: 1 }).ok" >/dev/null 2>&1; do
        sleep 1
        counter=$((counter + 1))
        if [ "$counter" -gt "$maxcounter" ]; then
            echo "ERROR: MongoDB did not start in time"
            exit 1
        fi
    done
    echo "MongoDB is responding"
}

# RELIABLE: Use rs.isMaster() to detect if THIS node is primary
is_current_node_primary() {
    mongosh --quiet --eval "rs.isMaster().ismaster" 2>/dev/null | grep -q "true"
}

# Wait until this node becomes PRIMARY
wait_for_primary_election() {
    local maxcounter=120
    local counter=1
    echo "Waiting for replica set election and current node PRIMARY status..."
    while ! is_current_node_primary; do
        sleep 2
        counter=$((counter + 1))
        if [ "$counter" -gt "$maxcounter" ]; then
            echo "WARNING: Current node is not PRIMARY after $maxcounter seconds. Skipping user setup."
            return 1
        fi
    done
    echo "Current node elected as PRIMARY"
    return 0
}

# Run Python activation script
run_activation_script() {
    if [ -f "$YAML_FILE" ]; then
        echo "Found setup.yaml, running activation script..."
        python3 /appz/scripts/activate_mongo.py
        if [ $? -eq 0 ]; then
            echo "activate_mongo.py script completed successfully"
        else
            echo "WARNING: activate_mongo.py encountered issues"
            return 1
        fi
    else
        echo "No setup.yaml found, skipping activation script"
    fi
}

# --- 3. MAIN LOGIC ---
if [ "$REPLICATION" -gt 1 ]; then
    echo "MongoDB Replica Set Mode Enabled"
    wait_for_mongo
    if wait_for_primary_election; then
        echo "PRIMARY node detected. Creating admin user and running activation script."
        echo "Ensuring admin user exists..."
        JS_PWD=$(python3 -c "import json; print(json.dumps('$DB_USER_ADMIN_PASSWORD'))")
        mongosh --quiet admin --eval "
          if (db.getUser('$DB_USER_ADMIN') == null) {
            db.createUser({
              user: '$DB_USER_ADMIN',
              pwd: $JS_PWD,
              roles: ['root']
            });
            print('Admin user created');
          } else {
            print('Admin user already exists');
          }
        " 2>/dev/null || echo "Note: Admin user may already exist from start.sh"
        run_activation_script
        echo "User creation and activation complete on PRIMARY."
    else
        echo "Node is not Primary. Skipping user creation and setup script."
    fi

elif [ "$REPLICATION" -le 1 ] && [ "$AUTH_ENABLE" -eq 1 ]; then
    echo "MongoDB Standalone with Authentication"
    maxcounter=90
    counter=1
    echo "Waiting for MongoDB to listen on port 27017..."
    while ! netstat -tln | grep '27017' >/dev/null 2>&1; do
        sleep 1
        counter=$((counter + 1))
        if [ "$counter" -gt "$maxcounter" ]; then
            echo "ERROR: MongoDB did not start listening in time"
            exit 1
        fi
    done
    echo "MongoDB is listening on port 27017"
    echo "Ensuring admin user exists..."
    JS_PWD=$(python3 -c "import json; print(json.dumps('$DB_USER_ADMIN_PASSWORD'))")
    mongosh --quiet admin --eval "
      if (db.getUser('$DB_USER_ADMIN') == null) {
        db.createUser({
          user: '$DB_USER_ADMIN',
          pwd: $JS_PWD,
          roles: ['root']
        });
        print('Admin user created');
      } else {
        print('Admin user already exists');
      }
    " 2>/dev/null || echo "Note: Admin user may already exist from start.sh"
    echo "Restarting MongoDB with authentication..."
    PIDS_MONGO=$(ps aux | grep mongod | grep dbpath | grep -v grep | awk '{print $2}')
    if [ -n "$PIDS_MONGO" ]; then
        echo "Stopping MongoDB processes..."
        for PID in $PIDS_MONGO; do
            echo "Killing process: $PID"
            kill "$PID" 2>/dev/null || true
        done
        sleep 2
        while ps aux | grep mongod | grep dbpath | grep -v grep >/dev/null 2>&1; do
            sleep 1
        done
    fi
    echo "Waiting for MongoDB to restart..."
    sleep 2
    wait_for_mongo
    echo "MongoDB standalone is ready"
    run_activation_script

elif [ "$REPLICATION" -eq 0 ] && [ "$AUTH_ENABLE" -eq 0 ]; then
    echo "MongoDB Standalone without Authentication"
    wait_for_mongo
    echo "MongoDB standalone is ready (no auth)"
    run_activation_script

else
    echo "Unknown configuration: REPLICATION=$REPLICATION, AUTH_ENABLE=$AUTH_ENABLE"
    echo "Skipping user setup"
fi

echo "addusers script completed successfully"
exit 0
