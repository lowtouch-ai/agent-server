#!/bin/bash
source /appz/scripts/.env
L=/appz/log/cleanup.log
RT="${BACKUP_RETENTION:-7}"
echo "INFO backup retention period :- $RT days" | tee -a $L
echo "$T> cleaning up cache files" >> $L
find /appz/cache -type f -mtime +3 -exec rm -fv {} \; | tee -a $L

echo "$T> cleaning up backup files" >> $L
find /appz/backup -mindepth 1 -maxdepth 1 -type f,d -mtime +"$RT" -not -name archives -exec rm -rf {} \; | tee -a $L
find /appz/backup -mindepth 1 -maxdepth 1 -type f,d -mtime +365 -name archives -exec rm -rf {} \; | tee -a $L


echo "$T> cleaning up complete!"  >> $L
