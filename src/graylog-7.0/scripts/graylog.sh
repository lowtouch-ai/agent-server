#!/bin/bash
PORT=9200
URL="http://opensearch:$PORT/_cluster/health?pretty"
CLUSTER_URL="${GRAYLOG_ELASTICSEARCH_HOSTS}_cluster/health?pretty"
GRAYLOG_MONGODB_URL=$(echo "$GRAYLOG_MONGODB_URI" | awk -F[/:] '{print $4":"$5"/"$NF}')
SECONDS=0
end=$((SECONDS+30));
of=$((end-SECONDS)) ;

export GRAYLOG_PLUGIN_DIR=/usr/share/graylog/plugins-merged
rm -f /usr/share/graylog/plugins-merged/*
find /usr/share/graylog/plugins-default/ -type f -exec cp {} /usr/share/graylog/plugins-merged/ \;
find /usr/share/graylog/plugin/ -type f -exec cp {} /usr/share/graylog/plugins-merged/ \;

while  [ $SECONDS -lt $end ];
do
   if [[ "${CLUSTER_MODE:-0}" -eq 1 ]] ; then
      response="$(curl -s "$CLUSTER_URL" | grep '"status"' | awk '{print $3}' | tr -d '",')"
      status_code="$(curl --write-out %{http_code} --silent --output /dev/null http://$GRAYLOG_MONGODB_URL)"
   else
      response="$(curl -s "$URL" | grep '"status"' | awk '{print $3}' | tr -d '",')"
      status_code="$(curl --write-out %{http_code} --silent --output /dev/null http://mongo:27017)"
   fi

   if [[ "$response" =~ "green" ]]; then
     echo "Opensearch is running on  $URL"
   elif [[ "$response" =~ "red" ]]; then
      echo "Opensearch Server $URL is down\n"
   elif [[ "$response" =~ "yellow" ]]; then
      echo "Opensearch  server $URL  shards are allocating\n"
   else [[ "$response" == "" ]];
       echo "Opensearch process is not running in $URL"
   fi

   if [[ "$status_code" -eq 200 ]] ; then
      echo "Mongo db is up and running with status code  $status_code"
   else
    echo "Mongo db is not running and trying to reconnect"
   fi

   if [[ "$response" =~ "green" && "$status_code" -eq 200 ]]; then

        break
   fi
   sleep 5
done

if [[ $(crontab -l | grep "minio_backup") ]]; then
  echo "$(date +%Y%m%d-%H%M%S) INFO Cron job for minio_backup already exists"
else
  (crontab -l ; echo "0 ${MINIO_BACKUP_TIME:-07} * * * supervisorctl start minio_backup") | crontab -
  echo "$(date +%Y%m%d-%H%M%S) INFO Cron job for minio_backup added"
fi

if [ "${CLEAR_JOURNAL:-0}" = 1 ]; then
    rm -rf /usr/share/graylog/data/journal/*
    echo "Journal cleared."
fi
echo "Starting graylog"

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
sed -i 's/root_password_sha2 =.*/root_password_sha2 = '$GRAYLOG_ROOT_PASSWORD_SHA2'/g' /usr/share/graylog/data/config/graylog.conf
sed -i 's/password_secret =.*/password_secret = '$GRAYLOG_PASSWORD_SECRET'/g' /usr/share/graylog/data/config/graylog.conf
sed -i 's/output_batch_size = 500/output_batch_size = '${OUTPUT_BATCH_SIZE:-100}'/g' /usr/share/graylog/data/config/graylog.conf

CONFIG_FILE="/usr/share/graylog/data/config/graylog.conf"
sed -i 's/#root_timezone = UTC/root_timezone = Asia\/Kolkata/' "$CONFIG_FILE"

if grep -q 'root_timezone = Asia/Kolkata' "$CONFIG_FILE"; then
    echo "Timezone update successful."
else
    echo "Timezone update failed."
fi

if [ ${AUTH_EMAIL_ENABLE:-0} = 1 ];then
 echo "email enabled"

 sed -i 's/#transport_email_enabled = false/transport_email_enabled = true/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_hostname = mail.example.com/transport_email_hostname = '$GRAYLOG_TRANSPORT_EMAIL_HOSTNAME'/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_port = 587/transport_email_port = '$GRAYLOG_TRANSPORT_EMAIL_PORT'/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_use_auth = true/transport_email_use_auth = '$GRAYLOG_TRANSPORT_EMAIL_USE_AUTH'/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_use_tls = true/transport_email_use_tls = '$GRAYLOG_TRANSPORT_EMAIL_USE_TLS'/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_use_ssl = true/transport_email_use_ssl = '$GRAYLOG_TRANSPORT_EMAIL_USE_SSL'/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_auth_username = you@example.com/transport_email_auth_username = '$GRAYLOG_TRANSPORT_EMAIL_AUTH_USERNAME'/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_auth_password = secret/transport_email_auth_password = '$GRAYLOG_TRANSPORT_EMAIL_AUTH_PASSWORD'/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_subject_prefix = \[graylog\]/transport_email_subject_prefix = \[graylog\]/g' /usr/share/graylog/data/config/graylog.conf
 sed -i 's/#transport_email_from_email = graylog@example.com/transport_email_from_email = '$GRAYLOG_TRANSPORT_EMAIL_FROM_EMAIL'/g' /usr/share/graylog/data/config/graylog.conf

else
 echo "Transport Email Not Configured"
fi

if [ "$NODE_MODE" == "" ]; then
 echo "Creating Single Node Graylog"

else

   if [[ "$NODE_MODE" == "multi-node" ]]; then
     POD=`echo $HOSTNAME |awk '{print substr($0,length,1)}'`
     if [[ "$POD" != "0" ]]; then
      sed -i 's/is_leader = true/is_leader = false/g' /usr/share/graylog/data/config/graylog.conf
     fi
   fi
fi
if [ ${RETENTION_ENABLE:-0} = 1 ]; then
 check_error() {
    if [ $? -ne 0 ]; then
      echo "Error: sed operation failed. Exiting script."
      exit 1
    fi
 }

 sed -i 's/rotation_strategy = count/rotation_strategy = time/g' /usr/share/graylog/data/config/graylog.conf
 check_error
 sed -i 's/opensearch_max_docs_per_index = 20000000/#opensearch_max_docs_per_index = 20000000/g' /usr/share/graylog/data/config/graylog.conf
 check_error
 sed -i 's/#opensearch_max_time_per_index = 1d/opensearch_max_time_per_index = '${OPENSEARCH_INDEX_TIME:-1d}'/g' /usr/share/graylog/data/config/graylog.conf
 check_error
 sed -i 's/opensearch_max_number_of_indices = 20/opensearch_max_number_of_indices = '${OPENSEARCH_TOTAL_INDICES:-20}'/g' /usr/share/graylog/data/config/graylog.conf
 check_error
 sed -i 's/opensearch_replicas = 0/opensearch_replicas = '${OPENSEARCH_NUMBEROF_REPLICAS:-0}'/g' /usr/share/graylog/data/config/graylog.conf
 check_error
fi
sed -i 's/#message_journal_max_size = 5gb/message_journal_max_size = '${GRAYLOG_JOURNAL_MAX_SIZE:-5gb}'/g' /usr/share/graylog/data/config/graylog.conf
sed -i '/^ring_size = 65536$/ s/65536/'${RING_SIZE:-65536}'/' /usr/share/graylog/data/config/graylog.conf
if [ -n "$JAVA_HEAP_SIZE" ]; then
  exec java -jar -Dlog4j.configurationFile=/usr/share/graylog/data/config/log4j2.xml -Xms"${JAVA_HEAP_SIZE}" -Xmx"${JAVA_HEAP_SIZE}" -Djava.library.path=/usr/share/graylog/lib/sigar/ -Dgraylog2.installation_source=docker /usr/share/graylog/graylog.jar server -f /usr/share/graylog/data/config/graylog.conf
else
  exec java -jar -Dlog4j.configurationFile=/usr/share/graylog/data/config/log4j2.xml -Djava.library.path=/usr/share/graylog/lib/sigar/ -Dgraylog2.installation_source=docker /usr/share/graylog/graylog.jar server -f /usr/share/graylog/data/config/graylog.conf
fi
