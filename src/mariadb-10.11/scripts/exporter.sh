#!/bin/bash

FLU=$(curl -sL -o /dev/null -w \"%{http_code}\" http://localhost:24220/api/plugins.json)
i=1
while [ $FLU != '"200"' ];
do
        if [ $i -le 12 ];then
                FLU=$(curl -sL -o /dev/null -w \"%{http_code}\" http://localhost:24220/api/plugins.json)
                echo "Waiting for the fluentd to come up..."
                sleep 5
                i=`expr $i + 1`
        else
                echo "WARN: Fluentd check timeout... exiting"
                break;
        fi
done


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

export DATA_SOURCE_NAME="root:$MYSQL_ROOT_PASSWORD@(localhost:3306)/"
exec /usr/local/bin/mysqld_exporter

