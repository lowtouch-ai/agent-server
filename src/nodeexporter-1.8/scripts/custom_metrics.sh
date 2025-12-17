#!/bin/bash

if [ "$ENABLE_UMS_METRICS" = "1" ]; then
    echo "Starting metrics collection script..."
    exec /opt/venv/bin/python /appz/scripts/metrics.py
else
    echo "ENABLE_UMS_METRICS env is not set, Skipping log_metrics collection"
fi

