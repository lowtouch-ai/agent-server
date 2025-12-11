#!/bin/bash

if [ -z "${FILE_PURGE_TIME}" ]; then
        echo "FILE_PURGE_TIME env not set. Exiting..."
        exit 1
else
        DAY=`echo ${FILE_PURGE_TIME} | awk -F"-" '{print $1}'`
        TIME=`echo ${FILE_PURGE_TIME} | awk -F"-" '{print $2}'`
        echo "Clean up will be scheduled to run at $FILE_PURGE_TIME"
fi

FLU=$(curl -sL -o /dev/null -w \"%{http_code}\" http://localhost:24220/api/plugins.json)
while [ $FLU != '"200"' ];
do
        FLU=$(curl -sL -o /dev/null -w \"%{http_code}\" http://localhost:24220/api/plugins.json)
        echo "Waiting for the fluentd to come up..."
        sleep 5
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


POD=`echo $HOSTNAME |awk '{print substr($0,length,1)}'`
if [[ "$POD" = "0" ]]; then
        LF_CLEANUP_DIR=/appz/log
        LF_CLEANUP=$LF_CLEANUP_DIR/website_cleanup.log
        touch $LF_CLEANUP
        chmod 664 $LF_CLEANUP
        if [ "$ENABLE_HA" == "yes" ]; then
             echo "enabling HA mode"
             export MYSQL_HOST=127.0.0.1:3306
        fi
        job_number=`echo "python3 /appz/scripts/website_cleanup.py 2>&1 | tee -a $LF_CLEANUP" | at $TIME $DAY 2>&1 | grep job | awk '{print $2}'`
        if [ -z "${job_number}" ]; then
                echo "ERROR Job scheduling failed. Invalid FILE_PURGE_TIME"
                exit 1
        elif [ "$job_number" = "refusing" ]; then
                echo "ERROR refusing to create job destined in the past"
                exit 1
        elif ! [[ "$job_number" =~ ^[0-9]+$ ]]; then
                echo "ERROR Job scheduling failed. Invalid FILE_PURGE_TIME"
                exit 1
        else
                echo "Job-$job_number Scheduled for Website Cleanup at $FILE_PURGE_TIME"
        fi
else
        echo "Skipping pod $POD"
fi

