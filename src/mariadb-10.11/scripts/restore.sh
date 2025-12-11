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
LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
LF_DIR=/appz/log
LF_CA=/appz/cache/
LF=$LF_DIR/db-restore.log
LR=/app
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
source /appz/scripts/.env
dir=/appz/backup/
if  test $# -eq 0 ; then
      echo "restore.sh [arguments]"
      echo "example:- ./restore.sh -f \"/appz/backup\""
      echo "options:"
      echo "-d backupfolder       to import the lastest file from the backup folder"
      echo "-f backupfile         to import a specific file"
      exit 0

fi

while test $# -gt 0; do
        case "$1" in
                -f)
                        shift
                        if test $# -gt 0; then
                                BACKUPFILE=$1
                                bf=`echo ${BACKUPFILE##*/} | awk -F '-' '{print $1"-"$2}'` 

                                if [ -f "$BACKUPFILE" ] && [ "$bf" = "db-wordpress" ]  ;then
                                     echo $LOGDATE "INFO mariadb restoring script started with file :$BACKUPFILE" |tee -a $LF
                                     mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} < $BACKUPFILE 2>$LF_CA/database.err
                                     if [ "$?" -eq 0 ]
                                     then

                                           echo $LOGDATE "INFO restored status :success" |tee -a $LF
                                           echo $LOGDATE "INFO restored user :$MYSQL_USER" |tee -a $LF
                                           echo $LOGDATE "INFO restored backup to db :${MYSQL_DATABASE}" |tee -a $LF
                                           echo $LOGDATE "INFO restored time :$LOGDATE" |tee -a $LF
                                           echo $LOGDATE "INFO restored file :$BACKUPFILE" |tee -a $LF
                                     else
                                           echo $LOGDATE "INFO restored status :not success" |tee -a $LF
                                           echo "Mysql restore encountered a problem look in $LF for information"
                                     fi

                                else
                                     echo $LOGDATE "ERROR no backup file specified with name:db-wordpress or not found; -h, --help for help" |tee -a $LF
                                     exit 1
                                fi
                        fi
                        shift
                        ;;
                -d)
                        shift
                        if test $# -gt 0; then
                                BACKUPFOLDER=$1
                                backup_file=`ls -t $BACKUPFOLDER/db-$MYSQL_DATABASE-* | head -1`
                                if [ -f "$backup_file" ] ; then
                                     while true; do
                                          echo $LOGDATE "INFO mariadb restoring script started with file :$backup_file" |tee -a $LF
                                          read -p "Restore file from backup $backup_file? [y/n] " yn
                                          case $yn in
                                              [Yy]* ) mysql -u ${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} < $backup_file  2>$LF_CA/database.err
                                                      if [ "$?" -eq 0 ]
                                                      then

                                                           echo $LOGDATE "INFO restored status :success" |tee -a $LF;\
                                                           echo $LOGDATE "INFO restored user :$MYSQL_USER" |tee -a $LF;\
                                                           echo $LOGDATE "INFO restored backup to db :${MYSQL_DATABASE}" |tee -a $LF;\
                                                           echo $LOGDATE "INFO restored time :$LOGDATE" |tee -a $LF;\
                                                           echo $LOGDATE "INFO restored file :$backup_file" |tee -a $LF;\
                                                      else
                                                          echo $LOGDATE "INFO restored status: not success" |tee -a $LF
                                                          echo "Mysql restore encountered a problem look in $LF for information";\

                                                      fi
                                                      break;;
                                              [Nn]* ) echo $LOGDATE "ERROR the user rejected the confirmation" |tee -a $LF; exit;;
                                              * ) echo "Please answer yes or no.";;
                                          esac
                                     done
                                else
                                     echo $LOGDATE "ERROR no backup folder specified or not found; -h, --help for help" |tee -a $LF
                                     exit 1
                                fi
                        fi
                        shift
                        ;;
                -h|*)
                        echo "restore.sh [arguments]"
                        echo "example:- ./restore.sh -f \"/appz/backup\""
                        echo "options:"
                        echo "-d backupfolder       to import the lastest file from the backup folder"
                        echo "-f backupfile         to import a specific file"
                        exit 0
                        ;;

        esac
done
cat $LF_CA/database.err |tee -a $LF
rm $LF_CA/database.err
echo $LOGDATE "INFO mariadb restoring script end" |tee -a $LF
