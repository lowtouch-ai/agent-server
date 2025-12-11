#!/bin/bash
source /appz/scripts/.env
L=/appz/log/backup.log
BE="${BACKUP_ENABLED:-1}"
echo "BACKUP_ENABLED VALUE=$BE" | tee -a $L
if [[ "${BE}" = "0" ]]; then
   echo "FOUND BACKUP_ENABLED FROM ENV..." | tee -a $L
   echo "BACKUP_ENABLED VALUE=$BE exiting backup script..." | tee -a $L
   sleep 3
   exit 0
fi
VERBOSE="${WP_BACKUP_VERBOSE:-1}"
if [[ "$VERBOSE" = "1" ]]; then
   #back up the upload files on everyday
   cd /var/www/html/wp-content/
   zip -r -v "/appz/backup/uploads-$(date +"%Y%m%d-%H%M").zip" uploads >> $L


elif [[ "$VERBOSE" = "0" ]]; then
   LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
   echo "$LOGDATE INFO cleaning up backup files" | tee -a $L
   RT="${BACKUP_RETENTION:-7}"
   echo "$LOGDATE INFO backup retention period :- $RT days" | tee -a $L
   #find /appz/backup -mindepth 1 -maxdepth 1 -type f,d -mtime +"$RT" -not -name archives -exec rm -rf {} \; | tee -a $L
   RT=$((RT-1))
   echo "mtime $RT"
   find /appz/backup -mindepth 1 -maxdepth 1 -type f,d -mtime +"$RT" -not -name archives -exec rm -rfv {} \; | tee -a $L
   POD=$(echo $HOSTNAME | awk '{print substr($0,length,1)}')
   if [ ${ALTERNATE_BACKUP_ENABLED:-0} = 1 ];then
    DAY_OF_MONTH=$(date +"%d")
    if [[ $POD = "0" ]]; then
        if (( DAY_OF_MONTH % 2 == 0 )); then
            echo "$(date +"%Y-%m-%d %H:%M:%S") INFO Taking backup on even day" | tee -a $L
            cd /var/www/html/wp-content/
            zip_date="`date +%Y%m%d-%H%M`"
            zip_name="upload-$zip_date.zip"
            zip -r -q "/appz/backup/$zip_name" uploads >> $L
            if [ "$?" -eq 0 ]
            then
             echo $LOGDATE "INFO backup Completed" |tee -a $L
             zipinfo -t "/appz/backup/$zip_name" |tee -a $L
             zip -T "/appz/backup/$zip_name" >> $L
             if [ "$?" -eq 0 ]
              then
               echo $LOGDATE "INFO backup validated successfully " |tee -a $L
             else
              echo $LOGDATE "INFO backup validation failed " |tee -a $L
             fi
            else
           echo $LOGDATE "INFO $line backup not Completed" |tee -a $L
           zip -T "/appz/backup/$zip_name" |tee -a $L
           fi
        fi

    elif [[ $POD != "0" ]]; then
        if (( DAY_OF_MONTH % 2 != 0 )); then
            echo "$(date +"%Y-%m-%d %H:%M:%S") INFO Taking backup on odd day" | tee -a $L
            cd /var/www/html/wp-content/
            zip_date="`date +%Y%m%d-%H%M`"
            zip_name="upload-$zip_date.zip"
            zip -r -q "/appz/backup/$zip_name" uploads >> $L
            if [ "$?" -eq 0 ]
            then
             echo $LOGDATE "INFO backup Completed" |tee -a $L
             zipinfo -t "/appz/backup/$zip_name" |tee -a $L
             zip -T "/appz/backup/$zip_name" >> $L
             if [ "$?" -eq 0 ]
              then
               echo $LOGDATE "INFO backup validated successfully " |tee -a $L
             else
              echo $LOGDATE "INFO backup validation failed " |tee -a $L
             fi
            else
           echo $LOGDATE "INFO $line backup not Completed" |tee -a $L
           zip -T "/appz/backup/$zip_name" |tee -a $L
           fi
        fi
    fi
   else
    echo "$LOGDATE INFO start backup script ..." | tee -a $L
     cd /var/www/html/wp-content/
     zip_date="`date +%Y%m%d-%H%M`"
     zip_name="upload-$zip_date.zip"

     zip -r -q "/appz/backup/$zip_name" uploads >> $L

     if [ "$?" -eq 0 ]
     then
        echo $LOGDATE "INFO backup Completed" |tee -a $L
        zipinfo -t "/appz/backup/$zip_name" |tee -a $L
        zip -T "/appz/backup/$zip_name" >> $L
        if [ "$?" -eq 0 ]
        then
           echo $LOGDATE "INFO backup validated successfully " |tee -a $L
        else
          echo $LOGDATE "INFO backup validation failed " |tee -a $L
        fi
     else
        echo $LOGDATE "INFO $line backup not Completed" |tee -a $L
        zip -T "/appz/backup/$zip_name" |tee -a $L
     fi

fi
fi
