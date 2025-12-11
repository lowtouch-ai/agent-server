#!/bin/bash
#
source /appz/scripts/.env
VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
BACKUP_DIR="/appz/backup"
mkdir -p $BACKUP_DIR
chmod 777 $BACKUP_DIR
SERIAL="`date +%Y_%m_%d_%H_%M`"
LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
DBLIST=$(su - postgres -c "psql -l -t | cut -d'|' -f1 | sed -e 's/ //g' -e '/^$/d'")
LF="/appz/log/backup.log"
METRICS_FILE="/appz/backup/backup_metrics.prom"
METRICS_PORT=${METRICS_PORT:-8006}  # Default to port 8006, override with METRICS_PORT env var

# Temporary storage for metrics data
declare -A BACKUP_STATUS
declare -A BACKUP_DURATION
ALL_DB_BACKUP_SIZE=0  # Single variable for all_db backup size (no array)

# Metrics setup only if ENABLE_BACKUP_METRIC=1
if [[ "$ENABLE_BACKUP_METRIC" == "1" ]]; then
  mkdir -p $(dirname $METRICS_FILE)
  touch $METRICS_FILE
  chmod 644 $METRICS_FILE

  # Write metrics headers without heredoc
  echo "# HELP pg_backup_status Status of the PostgreSQL backup (1 = success, 0 = failure)" > $METRICS_FILE
  echo "# TYPE pg_backup_status gauge" >> $METRICS_FILE
  echo "# HELP pg_backup_timestamp Timestamp of the last backup (Unix epoch)" >> $METRICS_FILE
  echo "# TYPE pg_backup_timestamp gauge" >> $METRICS_FILE
  echo "# HELP pg_backup_duration Duration of the backup process in milliseconds" >> $METRICS_FILE
  echo "# TYPE pg_backup_duration gauge" >> $METRICS_FILE
  echo "# HELP pg_backup_size Size of the all_db backup file in bytes" >> $METRICS_FILE
  echo "# TYPE pg_backup_size gauge" >> $METRICS_FILE

  # Function to store metrics data (size only for all_db)
  store_metrics() {
    local db_name=$1
    local status=$2
    local duration=$3
    local size=$4
    BACKUP_STATUS["$db_name"]=$status
    BACKUP_DURATION["$db_name"]=$duration
    if [[ "$db_name" == "all_db" && -n "$size" ]]; then
      ALL_DB_BACKUP_SIZE=$size
    fi
  }
else
  # Dummy function if metrics are disabled
  store_metrics() {
    : # No-op (do nothing)
  }
fi

# Backup individual databases
for i in $DBLIST; do
  if [ "$i" != "postgres" ] && [ "$i" != "template0" ] && [ "$i" != "template1" ] && [ "$i" != "template_postgis" ]; then
    DB=$i
    echo Dumping $i to $BACKUP_DIR/$DB\_$SERIAL.sql
    START_TIME=$(date +%s%3N)  # Capture time in milliseconds
    if su - postgres -c "pg_dump --clean --if-exists -U postgres $i > $BACKUP_DIR/$DB\_$SERIAL.sql"; then
      END_TIME=$(date +%s%3N)  # Capture time in milliseconds
      DURATION=$((END_TIME - START_TIME))  # Duration in milliseconds
      zip -jrm $BACKUP_DIR/$DB\_$SERIAL.zip $BACKUP_DIR/$DB\_$SERIAL.sql | tee -a $LF
      echo "$LOGDATE INFO Backuping DB: $DB" | tee -a $LF
      echo "$LOGDATE INFO $DB backup Completed" | tee -a $LF
      store_metrics "$DB" 1 "$DURATION"  # No size for individual DBs
    else
      echo "$LOGDATE ERROR $DB backup Failed" | tee -a $LF
      store_metrics "$DB" 0 0  # No size for individual DBs
    fi
  fi
done

# Backup all databases if enabled
if [[ "$ALL_DB_BACKUP" == "1" || -z "${ALL_DB_BACKUP}" ]]; then
  echo $LOGDATE "INFO ALL DB backup is enabled" | tee -a $LF
  START_TIME=$(date +%s%3N)  # Capture time in milliseconds
  if su postgres -c "pg_dumpall > $BACKUP_DIR/all_db_$SERIAL.sql"; then
    END_TIME=$(date +%s%3N)  # Capture time in milliseconds
    DURATION=$((END_TIME - START_TIME))  # Duration in milliseconds
    zip -jrm $BACKUP_DIR/all_db_$SERIAL.zip $BACKUP_DIR/all_db_$SERIAL.sql | tee -a $LF
    SIZE=$(stat -c %s "$BACKUP_DIR/all_db_$SERIAL.zip" 2>/dev/null || echo 0)
    echo $LOGDATE "INFO All DB Backup Completed" | tee -a $LF
    store_metrics "all_db" 1 "$DURATION" "$SIZE"  # Store size for all_db
  else
    echo $LOGDATE "ERROR All DB Backup Failed" | tee -a $LF
    store_metrics "all_db" 0 0 0  # Size will remain 0
  fi
elif [[ "$ALL_DB_BACKUP" == "0" ]]; then
  echo $LOGDATE "ALL DB backup is not enabled, hence skipping.." | tee -a $LF
else
  echo $LOGDATE "Invalid value found for ALL_DB_BACKUP" | tee -a $LF
fi

# Upload to WebDAV
if [[ "$PUSH_BACKUP_WEBDAV" == "True" ]]; then
  echo "Pushing database backup dump to $WEBDAV_BACKUP_URL"
  if [ -z "$DAV_USERPASSWORD" ] || [ -z "$DAV_USER" ] || [ -z "$WEBDAV_BACKUP_URL" ]; then
    echo "Error: DAV_USERPASSWORD, DAV_USER, or WEBDAV_BACKUP_URL is not defined"
    exit 1
  fi
  echo "Uploading database dump"
  if curl -u $DAV_USER:$DAV_USERPASSWORD -T "$BACKUP_DIR/all_db_$SERIAL.zip" "$WEBDAV_BACKUP_URL"; then
    echo "Uploading completed successfully"
  else
    echo "Upload failed"
  fi
else
  echo "PUSH_BACKUP_WEBDAV variable is set to False"
fi

# Expose metrics on a port if ENABLE_BACKUP_METRIC=1
if [[ "$ENABLE_BACKUP_METRIC" == "1" ]]; then
  echo "$LOGDATE INFO Starting metrics server on port $METRICS_PORT" | tee -a $LF

  # Forcefully free the port
  echo "$LOGDATE INFO Checking for existing process on port $METRICS_PORT" | tee -a $LF
  if lsof -i:$METRICS_PORT >/dev/null 2>&1; then
    echo "$LOGDATE INFO Killing existing process on port $METRICS_PORT" | tee -a $LF
    lsof -ti :$METRICS_PORT | xargs kill -9 || {
      echo "$LOGDATE ERROR Failed to kill process on port $METRICS_PORT" | tee -a $LF
      exit 1
    }
    sleep 1  # Brief pause to ensure the port is released
  fi

  # Start the custom Python metrics server
  python3 - <<EOF &
import http.server
import socketserver
import os

PORT = $METRICS_PORT
METRICS_FILE = "$METRICS_FILE"

class MetricsHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            with open(METRICS_FILE, 'rb') as f:
                self.wfile.write(f.read())
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"404 Not Found")

os.chdir("$BACKUP_DIR")
with socketserver.TCPServer(("", PORT), MetricsHandler) as httpd:
    print(f"Serving metrics on port {PORT} at /metrics")
    httpd.serve_forever()
EOF
  METRICS_PID=$!

  # Verify the server started
  sleep 2  # Give it a moment to start
  if ps -p $METRICS_PID >/dev/null 2>&1; then
    echo "$LOGDATE INFO Metrics server started with PID $METRICS_PID" | tee -a $LF
  else
    echo "$LOGDATE ERROR Metrics server failed to start" | tee -a $LF
    exit 1
  fi
fi

# Write final metrics with timestamp only after everything is done
if [[ "$ENABLE_BACKUP_METRIC" == "1" ]]; then
  FINAL_TIMESTAMP=$(date +%s)  # Keep timestamp in seconds for consistency
  for db_name in "${!BACKUP_STATUS[@]}"; do
    echo "pg_backup_status{db=\"$db_name\"} ${BACKUP_STATUS[$db_name]}" >> $METRICS_FILE
    echo "pg_backup_timestamp{db=\"$db_name\"} $FINAL_TIMESTAMP" >> $METRICS_FILE
    echo "pg_backup_duration{db=\"$db_name\"} ${BACKUP_DURATION[$db_name]}" >> $METRICS_FILE
  done
  # Write the backup size only for all_db
  echo "pg_backup_size{db=\"all_db\"} $ALL_DB_BACKUP_SIZE" >> $METRICS_FILE
fi

