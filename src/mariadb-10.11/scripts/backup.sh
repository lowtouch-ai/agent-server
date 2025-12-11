#!/bin/bash
#
source /appz/scripts/.env
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
BACKUP_DIR="/appz/backup"
mkdir -p $BACKUP_DIR
chmod 777 $BACKUP_DIR
SERIAL="`date +%Y_%m_%d_%H_%M`"
LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
function LogStart
{
echo $LOGDATE " INFO mariadb backup script start" |tee -a $LF
}
function LogEnd
{
echo $LOGDATE "INFO mariadb backup script end" |tee -a $LF
}

function GetDBList
{
echo $LOGDATE "INFO Calling GetDBList()" |tee -a $LF
mysqlshow -p${MYSQL_ROOT_PASSWORD} \
    |grep "|"| tr -d ' '|tr -d '|'| egrep -v Databases > $DBLIST 2>/appz/cache/database.err
if [ "$?" -eq 0 ]
then
   echo $LOGDATE "INFO listed DB names" |tee -a $LF
else
   echo $LOGDATE "ERROR can't list DB names" |tee -a $LF
fi

}

function DoBackup
{
echo $LOGDATE "INFO Calling DoBackup()" |tee -a $LF

DBFILE=$BACKUP_DIR/db-$DB-$SERIAL.sql
echo $LOGDATE "INFO Host [$H]" >> $LF
echo $LOGDATE "INFO DB ${DB} backup to File $DBFILE" |tee -a $LF
if [ -a  $DBFILE ]
then
mv $DBFILE $DBFILE.`date '+%Y_%m_%d_%H:%M'`
fi
echo $LOGDATE "INFO Dumping ${DB}" |tee -a $LF
mysqldump -p${MYSQL_ROOT_PASSWORD} -B ${DB}  --add-drop-database --add-drop-table --lock-tables=false >> ${DBFILE} 2>/appz/cache/database.err
if [ "$?" -eq 0 ]
then
   echo "$LOGDATE INFO Backuping DB: $line" |tee -a $LF
   echo $LOGDATE "INFO $line backup Completed" |tee -a $LF
else
   echo $LOGDATE "ERROR fail to backup DB: $line" |tee -a $LF
   echo $LOGDATE "INFO $line backup not Completed" |tee -a $LF
fi

}

FILE_DATE=`date '+%Y_%m_%d_%H:%M'`
LF_DIR=/appz/log
LF=$LF_DIR/db-backup.log
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF

DBLIST=/appz/cache/dblist-$FILE_DATE.list

LogStart

GetDBList
while read line
do
H="localhost"
DB=$line
DoBackup
done < $DBLIST
LogEnd
rm  $DBLIST
rm /appz/cache/database.err
