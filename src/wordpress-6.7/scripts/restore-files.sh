#!/bin/bash
LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
LF_DIR=/appz/log
LF=$LF_DIR/restore.log
touch $LF
chmod 664 $LF
BACKUPFOLDER=/appz/backup
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
                -h|--help)
                        echo "restore.sh [arguments]"
                        echo "example:- ./restore.sh -f "/appz/backup""
                        echo "options:"
                        echo "-h, --help            show brief help"
                        echo "-d backupfolder       to import the lastest file from the backup folder"
                        echo "-f backupfile         to import a specific file"
                        exit 0
                        ;;
                -f)
                        shift
                        if test $# -gt 0; then
                                BACKUPFILE=$1
                                backup_file=$BACKUPFILE
                                if [ -f "$backup_file" ] ;then
                                    read -p "you want to restore the backup file $backup_file Y/N: " -n 1 -r
                                    if [[ $REPLY =~ ^[Yy]$ ]]
                                    then
                                        cd /appz/data/;
                                        unzip -o $backup_file | tee -a $LF
                                        echo $LOGDATE "INFO restored status :success" |tee -a $LF
                                        echo $LOGDATE "INFO restored backup file $backup_file to /appz/data/ folder :" |tee -a $LF
                                        echo $LOGDATE "INFO restored time :$LOGDATE" |tee -a $LF
                                        echo $LOGDATE "INFO restored file :$backup_file" |tee -a $LF
                                    else
                                        echo $LOGDATE "INFO restored status :not success" |tee -a $LF
                                        echo $LOGDATE "Upload data restore encountered a problem,for more info look in $LF" | tee -a $LF
                                    fi
                                else
                                    echo $LOGDATE "NO such file found /appz/backup" | tee -a $LF                                fi
                                fi
                        fi
                        shift
                        ;;
                -d)
                        shift
                        if test $# -gt 0; then
                                BACKUPFOLDER=$1
                                backup_file=`ls -t $BACKUPFOLDER/uploads-* | head -1`
                                if [ -f "$backup_file" ] ;then
                                    read -p "you want to restore the backup file $backup_file Y/N: " -n 1 -r
                                    if [[ $REPLY =~ ^[Yy]$ ]]
                                    then
                                        cd /appz/data/;
                                        unzip -o $backup_file | tee -a $LF
                                        echo $LOGDATE "INFO restored status :success" |tee -a $LF
                                        echo $LOGDATE "INFO restored backup file $backup_file to /appz/data/ folder :" |tee -a $LF
                                        echo $LOGDATE "INFO restored time :$LOGDATE" |tee -a $LF
                                        echo $LOGDATE "INFO restored file :$backup_file" |tee -a $LF
                                    else
                                         echo $LOGDATE "INFO restored status :not success" |tee -a $LF
                                         echo $LOGDATE "Upload data restore encountered a problem,for more info look in $LF" | tee -a $LF
                                    fi
                                else
                                    echo $LOGDATE "NO such file found /appz/backup" | tee -a $LF                          
                                fi
                        fi
                        shift
                        ;;
                *)
                        break
                        ;;
        esac
done

