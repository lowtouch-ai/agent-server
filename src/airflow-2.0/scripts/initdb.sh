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



TRY_LOOP="20"
wait_for_port() {
  local name="$1" host="$2" port="$3"
  local j=0
  while ! nc -z "$host" "$port" >/dev/null 2>&1 < /dev/null; do
    j=$((j+1))
    if [ $j -ge $TRY_LOOP ]; then
      echo >&2 "$(date) - $host:$port still not reachable, giving up"
      exit 1
    fi
    echo "$(date) - waiting for $name... $j/$TRY_LOOP"
    sleep 5
  done
}

if [[ -n "$AIRFLOW__CORE__EXECUTOR" && "$AIRFLOW__CORE__EXECUTOR" != "SequentialExecutor" ]]; then
  if [ -z "$AIRFLOW__DATABASE__SQL_ALCHEMY_CONN" ]; then
    : "${POSTGRES_HOST:="postgres"}"
    : "${POSTGRES_PORT:="5432"}"
    : "${POSTGRES_USER:="airflow"}"
    : "${POSTGRES_PASSWORD:="airflow"}"
    : "${POSTGRES_DB:="airflow"}"
    : "${POSTGRES_EXTRAS:-""}"

    AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}${POSTGRES_EXTRAS}"
    export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN

    if [[ "$AIRFLOW__CORE__EXECUTOR" == "CeleryExecutor" ]]; then
      AIRFLOW__CELERY__RESULT_BACKEND="db+postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}${POSTGRES_EXTRAS}"
      export AIRFLOW__CELERY__RESULT_BACKEND
    fi
  else
    if [[ "$AIRFLOW__CORE__EXECUTOR" == "CeleryExecutor" && -z "$AIRFLOW__CELERY__RESULT_BACKEND" ]]; then
      >&2 printf '%s\n' "FATAL: if you set AIRFLOW__DATABASE__SQL_ALCHEMY_CONN manually with CeleryExecutor you must also set AIRFLOW__CELERY__RESULT_BACKEND"
      exit 1
    fi

    POSTGRES_ENDPOINT=$(echo -n "$AIRFLOW__DATABASE__SQL_ALCHEMY_CONN" | cut -d '/' -f3 | sed -e 's,.*@,,')
    POSTGRES_HOST=$(echo -n "$POSTGRES_ENDPOINT" | cut -d ':' -f1)
    POSTGRES_PORT=$(echo -n "$POSTGRES_ENDPOINT" | cut -d ':' -f2)
  fi

  wait_for_port "Postgres" "$POSTGRES_HOST" "$POSTGRES_PORT"
fi

if [[ -n "$AIRFLOW__CORE__EXECUTOR" && "$AIRFLOW__CORE__EXECUTOR" == "CeleryExecutor" ]]; then
  if [ -z "$AIRFLOW__CELERY__BROKER_URL" ]; then
    : "${REDIS_PROTO:="redis://"}"
    : "${REDIS_HOST:="redis"}"
    : "${REDIS_PORT:="6379"}"
    : "${REDIS_PASSWORD:=""}"
    : "${REDIS_DBNUM:="1"}"

    if [ -n "$REDIS_PASSWORD" ]; then
      REDIS_PREFIX=":${REDIS_PASSWORD}@"
    else
      REDIS_PREFIX=
    fi

    AIRFLOW__CELERY__BROKER_URL="${REDIS_PROTO}${REDIS_PREFIX}${REDIS_HOST}:${REDIS_PORT}/${REDIS_DBNUM}"
    export AIRFLOW__CELERY__BROKER_URL
  else
    REDIS_ENDPOINT=$(echo -n "$AIRFLOW__CELERY__BROKER_URL" | cut -d '/' -f3 | sed -e 's,.*@,,')
    REDIS_HOST=$(echo -n "$REDIS_ENDPOINT" | cut -d ':' -f1)
    REDIS_PORT=$(echo -n "$REDIS_ENDPOINT" | cut -d ':' -f2)
  fi

  wait_for_port "Redis" "$REDIS_HOST" "$REDIS_PORT"
fi


exec airflow db migrate