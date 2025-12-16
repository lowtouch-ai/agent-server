#!/bin/bash

if env | grep "VAULT:" > /dev/null 2>&1
then
    c=1
    mc=180
    while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health | grep "200" > /dev/null 2>&1; do
        echo "waiting for $VAULT_ADDR..."
        sleep 1
        c=$(expr $c + 1)
        if [ $c -gt $mc ]; then
            echo "FATAL: vault timeout... exiting"
            exit 1
        fi
    done
    VAULT_GET_ADDR=$(echo $VAULT_ADDR | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
    source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi

connection_string="mongodb://$MONGO_USER:$MONGO_USER_PASSWORD@localhost:27017/$MONGO_DATABASE"

log_file="/appz/log/mongo.log"

current_time=$(date -u +"%Y-%m-%dT%H:%M:%S")
one_minute_ago=$(date -u --date="1 minute ago" +"%Y-%m-%dT%H:%M:%S")
one_minute_ago="${one_minute_ago}Z"

mongoexport --uri="$connection_string" \
    --collection=system.profile \
    --jsonArray \
    --query="{ \"ts\": { \"\$gte\": { \"\$date\": \"$one_minute_ago\" } } }" \
    | jq -c '.[] | select(.appName == "mongosh 1.7.1")' | while read -r line; do
        echo "$line" >> "$log_file"
        echo "" >> "$log_file"
    done

if [ $? -ne 0 ]; then
    echo "Error: Failed to connect to MongoDB or retrieve profiler data."
    exit 1
fi

echo "Filtered profiler data logged successfully to $log_file."
exit 0
