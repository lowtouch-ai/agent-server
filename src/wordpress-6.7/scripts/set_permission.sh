#! /bin/bash
file="/var/www/html/wp-content/uploads/"
fmod=0
fown=0
LOGDATE="`date +%Y_%b_%d_%H:%M:%S`"
LF_DIR=/appz/log
LF=$LF_DIR/set_permission.log
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
array1=(`find $file -type f`)
for i in "${array1[@]}"
        do :
                permission=(`ls -al $i | awk '{print $1}'`)
                owner=(`ls -al $i | awk '{print $3}'`)
                group=(`ls -al $i | awk '{print $4}'`)
                if [[ "$permission" == "-rwx------" ]]; then
                        chmod 755 $i 2>&1 | tee -a $LF
                        fmod="1"
                        echo $LOGDATE "Detected the file $i with permission 700 & changed to 755" |tee -a $LF
                fi
                if [[ "$owner" != "www-data" ]]; then
                        chown www-data:www-data $i 2>&1 | tee -a $LF
                        fown="1"
                        echo $LOGDATE "Detected the file $i with ownership $owner & changed to www-data" |tee -a $LF
                fi
        done
array2=(`find $file -type d | sed '1d'`)
for i in "${array2[@]}"
        do :
                permission=(`ls -ld $i | awk '{print $1}'`)
                owner=(`ls -ld $i | awk '{print $3}'`)
                if [[ "$permission" == "drwx------" ]]; then
                        chmod 755 $i 2>&1 | tee -a $LF
                        fmod="1"
                        echo $LOGDATE "Detected the folder $i with permission 700 & changed to 755" |tee -a $LF
                fi
                if [[ "$owner" != "www-data" ]]; then
                        chown www-data:www-data $i 2>&1 | tee -a $LF
                        fown="1"
                        echo $LOGDATE "Detected the folder $i with ownership $owner & changed to www-data" |tee -a $LF
                fi
        done
if [[ "$fmod" == "0" ]]; then
        echo $LOGDATE "No files/folders with 700 permission found!" |tee -a $LF
fi
if [[ "$fown" == "0" ]]; then
        echo $LOGDATE "No files/folders with incorrect ownership found!" |tee -a $LF
fi
