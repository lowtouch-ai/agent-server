#!/bin/bash

if env | grep -q "VAULT:"; then
   c=1
   mc=180
   while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health | grep -q "200"; do
       echo "waiting for $VAULT_ADDR..."
       sleep 1
       ((c++))
       if [ $c -gt $mc ]; then
           echo "FATAL: vault timeout... exiting"
           exit 1
       fi
   done
   VAULT_GET_ADDR=$(echo $VAULT_ADDR | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi
if [ ${ENABLE_MINIO_BACKUP:-0} = 1 ]; then
    echo "Minio Backup enabled for OpenSearch"
    exec python3 /appz/scripts/minio.py
else
    echo "ENV 'ENABLE_MINIO_BACKUP' not set, Skipping Minio Backup"
    sleep 2
    exit 0
fi

