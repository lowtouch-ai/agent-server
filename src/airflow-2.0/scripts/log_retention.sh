#!/bin/bash

cleanup_old_directories() {
  local log_dir=$1
  local log_retention=$2
  local log_type=$3

  find "$log_dir" -type d -name "$log_type" -exec bash -c '
    LOG_RETENTION=$1
    for dir in "${@:2}"; do
      find "$dir" -mindepth 1 -maxdepth 1 -type d -mtime +"$LOG_RETENTION" | while read -r old_dir; do
        relative_path="${old_dir#"$dir"/}"
        current_time=$(date +'%Y-%m-%dT%H:%M:%S%z')
        echo "{\"TIMESTAMP\": \"$current_time\", \"MSG\": \"Deleting directory $old_dir\"}"
        rm -rfv "$old_dir"
      done
    done
  ' _ "$log_retention" {} +

  if [ "$?" -eq 0 ]; then
    echo "$log_type directories older than $log_retention days have been removed!"
  else
    echo "Error occurred while cleaning up $log_type directories. Exiting!"
    exit 1
  fi
}

if [ -z "$AIRFLOW_LOG_RETENTION" ] || [ -z "$AIRFLOW_LOG_DIR" ]; then
  echo "AIRFLOW_LOG_RETENTION or AIRFLOW_LOG_DIR is not set. Exiting."
  sleep 10
  exit 0
fi

LOG_RETENTION=$AIRFLOW_LOG_RETENTION
LOG_DIR=$AIRFLOW_LOG_DIR

cleanup_old_directories "$LOG_DIR" "$LOG_RETENTION" "dag_id=*"

cleanup_old_directories "$LOG_DIR" "$LOG_RETENTION" "scheduler"

sleep 10
exit 0