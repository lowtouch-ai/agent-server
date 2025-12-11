#!/bin/bash
#
source /appz/scripts/.env
VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
BACKUP_DIR="/appz/backup"
mkdir -p $BACKUP_DIR
chmod 777 $BACKUP_DIR
SERIAL="`date +%Y_%m_%d_%H_%M`"
LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
DBLIST=$(su - postgres -c "psql -l -t | cut -d'|' -f1 | sed -e 's/ //g' -e '/^$/d'")
echo $DBLIST
LF="/appz/log/backup.log"
#Removing default databases from the backup job
for i in $DBLIST; do  if [ "$i" != "postgres" ] && [ "$i" != "template0" ] && [ "$i" != "template1" ] && [ "$i" != "template_postgis" ]; then
    DB=$i
    echo Dumping $i to $BACKUP_DIR/$DB\_$SERIAL.sql
    su - postgres -c "pg_dump --clean --if-exists -U postgres $i > $BACKUP_DIR/$DB\_$SERIAL.sql"
    zip -jrm $BACKUP_DIR/$DB\_$SERIAL.zip $BACKUP_DIR/$DB\_$SERIAL.sql |tee -a $LF
    echo "$LOGDATE INFO Backuping DB: $DB" |tee -a $LF
    echo $LOGDATE "INFO $DB backup Completed" |tee -a $LF
  fi
done

#Taking all db backups in single file
if [[ "$ALL_DB_BACKUP" == "1" ]]; then
  echo $LOGDATE "INFO ALL DB backup is enabled" |tee -a $LF
  su postgres -c pg_dumpall > $BACKUP_DIR/all_db_$SERIAL.sql |tee -a $LF
  zip -jrm $BACKUP_DIR/all_db_$SERIAL.zip $BACKUP_DIR/all_db_$SERIAL.sql |tee -a $LF
  echo $LOGDATE "INFO All DB Backup Completed" |tee -a $LF
elif [[ "$ALL_DB_BACKUP" == "0" ]]; then
  echo $LOGDATE "ALL DB backup is not enabled, hence skipping.." |tee -a $LF
elif [[ -z "${ALL_DB_BACKUP}" ]]; then
  echo $LOGDATE "Value for ALL_DB_BACKUP not found from env, hence taking default value as 1" |tee -a $LF
  su postgres -c pg_dumpall > $BACKUP_DIR/all_db_$SERIAL.sql |tee -a $LF
  zip -jrm $BACKUP_DIR/all_db_$SERIAL.zip $BACKUP_DIR/all_db_$SERIAL.sql |tee -a $LF
  echo $LOGDATE "INFO All DB Backup Completed" |tee -a $LF
else
  echo $LOGDATE "Invalid value found for ALL_DB_BACKUP" |tee -a $LF
fi

#Uploading backup to webdav
if [[ "$PUSH_BACKUP_WEBDAV" == "True" ]]; then
  echo "Pushing database backup dump to $WEBDAV_BACKUP_URL"
  if [ ! -z "$DAV_USERPASSWORD" ] ;
  then
    echo "Retrieved the value of DAV_USERPASSWORD"
  else
    echo "DAV_USERPASSWORD is not defined"
    exit 1
  fi

  if [ ! -z "$DAV_USER" ] ;
  then
    echo "Retrieved the value of DAV_USER"
  else
    echo "DAV_USER is not defined"
    exit 1
  fi

  if [ ! -z "$WEBDAV_BACKUP_URL" ] ;
  then
    echo "Retrieved the value of WEBDAV_BACKUP_URL" && echo "Uploading database dump"
    curl -u $DAV_USER:$DAV_USERPASSWORD -T "$BACKUP_DIR/all_db_$SERIAL.sql" "$WEBDAV_BACKUP_URL" && echo "Uploading completed successfully"
  fi
else
  echo "PUSH_BACKUP_WEBDAV variable is set to False"
fi
