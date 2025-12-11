#!/bin/sh
GITRUNNER_RSYNC="${GITRUNNER_RSYNC:-0}"

if [ "$GITRUNNER_RSYNC" -eq 0 ]; then
    echo "GITRUNNER_RSYNC is disabled."
    sleep 2
    exit 0
fi

LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"

if env | grep "VAULT:" > /dev/null 2>&1; then
    c=1
    mc=180
    while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health | grep "200" > /dev/null 2>&1; do
        echo "waiting for $VAULT_ADDR..."
        sleep 1
        c=`expr $c + 1`
        if [ $c -gt $mc ]; then
            echo "FATAL: vault timeout... exiting"
            exit 1
        fi
    done
    VAULT_GET_ADDR=$(echo $VAULT_ADDR | awk -F ':' '{print $1":"$2}' | sed 's/https/http/g')
    source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi

echo $LOGDATE "INFO rsync start "
echo $GITRUNNER_RSYNC_SECRET > /etc/rsyncd.local
chmod 600 /etc/rsyncd.*

echo rsync -avzh --delete --exclude='.user.yml' --password-file=/etc/rsyncd.local rsync://filesync@${GITRUNNER_RSYNC_HOST:-gitrunner}:${GITRUNNER_RSYNC_PORT:-12000}/dags ${AIRFLOW__CORE__DAGS_FOLDER:-/appz/home/airflow/dags}
rsync -avzh --delete --exclude='.user.yml' --password-file=/etc/rsyncd.local rsync://filesync@${GITRUNNER_RSYNC_HOST:-gitrunner}:${GITRUNNER_RSYNC_PORT:-12000}/dags ${AIRFLOW__CORE__DAGS_FOLDER:-/appz/home/airflow/dags} 2>&1

if [ $? -ge 1 ]; then
    echo $LOGDATE "RSYNC failed"
else
    echo $LOGDATE "RSYNC success"
fi

