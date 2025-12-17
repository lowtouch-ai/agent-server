#!/bin/bash
RT="${RETENTION_TIME:-15d}"
echo "$RT"
if [[ -f "/appz/scripts/init.sh" ]]; then
    bash "/appz/scripts/init.sh"
fi
exec /usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yaml --storage.tsdb.path=/appz/data --storage.tsdb.max-block-duration=2h --storage.tsdb.retention.time="$RT"
