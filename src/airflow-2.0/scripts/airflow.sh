#! /bin/bash
set -e

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


if [[ "$1" == "webserver" ]]; then
  if [[ -n "$KEYCLOAK_URL" ]]; then
    if [[ -z "$KEYCLOAK_CLIENT_ID" || -z "$KEYCLOAK_CLIENT_SECRET" ]]; then
        echo "FATAL: api credentials missing... exiting"
        exit 1
    else
      cp /appz/scripts/keycloak_config.py /appz/home/airflow/webserver_config.py
    fi
  else
    airflow users create -r Admin -u "$AIRFLOW_ADMIN_USERNAME" -e "$AIRFLOW_ADMIN_EMAIL" -f "$AIRFLOW_ADMIN_FIRSTNAME" -l "$AIRFLOW_ADMIN_LASTNAME" -p "$AIRFLOW_ADMIN_PASSWORD"
  fi
  if [[ -z "$AIRFLOW__CORE__EXECUTOR" ]]; then
    AIRFLOW__CORE__EXECUTOR="SequentialExecutor"
    export AIRFLOW__CORE__EXECUTOR
  fi

  if [[ "$AIRFLOW__CORE__EXECUTOR" == "LocalExecutor" || "$AIRFLOW__CORE__EXECUTOR" == "SequentialExecutor" ]]; then
    airflow scheduler &
    fi
  sleep 10
  exec airflow webserver
elif [[ "$1" == "scheduler" || "$1" == "worker" ]]; then
  sleep 10
  exec airflow "$@"
elif [[ "$2" == "worker" ]]; then
  sleep 10
  if [[ -z "$AIRFLOW_WORKER_QUEUE" ]]; then
    exec airflow celery worker --pid /appz/home/airflow/worker-$HOSTNAME.pid
  else
    exec airflow celery worker -q $AIRFLOW_WORKER_QUEUE --pid /appz/home/airflow/worker-$HOSTNAME.pid
  fi 
elif [[ "$2" == "flower" ]]; then
  sleep 10
  exec airflow celery flower

fi
