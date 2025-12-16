#!/bin/bash
if env |grep "VAULT:" > /dev/null 2>&1
then
   c=1
   mc=180
   while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health|grep "200"> /dev/null 2>&1;do
   echo "waiting for $VAULT_ADDR..."
   sleep 1
   c=`expr $c + 1`
   if [ $c -gt $mc ];then
      echo "FATAL: vault timeout... exiting"
      exit 1
   fi;done
   VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)

fi
# Verify that MINIO_SECRET_KEY is set (this is provided by Vault)
if [ -z "$MINIO_SECRET_KEY" ]; then
    echo "Error: MINIO_SECRET_KEY is not set. Aborting."
    exit 1
fi

# Set the encryption key in the required format: bucket_name:secret
export MINIO_KMS_SECRET_KEY="default:${MINIO_SECRET_KEY}"
export MINIO_KMS_MASTER_KEY="global-key:${MINIO_SECRET_KEY}"

# Start the MinIO server with the specified data directory and console address
exec minio server /appz/data --console-address :9001

