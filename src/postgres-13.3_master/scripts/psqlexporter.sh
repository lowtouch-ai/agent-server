#!/bin/bash

if [ "$ENABLE_FLUENTD" == "0" ]; then
    echo "Fluentd is disabled, skipping Fluentd check..."
else
    FLU=$(curl -sL -o /dev/null -w "%{http_code}" http://localhost:24220/api/plugins.json)
    while [ $FLU != "200" ]; do
        FLU=$(curl -sL -o /dev/null -w "%{http_code}" http://localhost:24220/api/plugins.json)
        echo "Waiting for Fluentd to come up..."
        sleep 5
    done
fi

if env | grep "VAULT:" > /dev/null 2>&1; then
    c=1
    mc=180
    while ! curl -k -o /dev/null -s -w "%{http_code}" $VAULT_ADDR/v1/sys/health | grep "200" > /dev/null 2>&1; do
        echo "Waiting for $VAULT_ADDR..."
        sleep 1
        c=$((c + 1))
        if [ $c -gt $mc ]; then
            echo "FATAL: Vault timeout... exiting"
            exit 1
        fi
    done
    VAULT_GET_ADDR=$(echo $VAULT_ADDR | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
    source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi

echo "Starting PostgreSQL exporter"
export DATA_SOURCE_NAME="postgresql://$POSTGRESQL_CONNECTUSER:$POSTGRES_PASSWORD@$POSTGRESQL_HOST:5432/$POSTGRESQL_CONNECTIONDB?sslmode=disable"
exec /usr/local/bin/postgres_exporter
