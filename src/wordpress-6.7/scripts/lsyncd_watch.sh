#!/bin/bash
POD=`echo $HOSTNAME |awk '{print substr($0,length,1)}'`
if [[ "$POD" = "0" ]]; then
        FILESYNC_REMOTE_IP="${HOSTNAME%?}1".${HOSTNAME::-2}
else
        FILESYNC_REMOTE_IP="${HOSTNAME%?}0".${HOSTNAME::-2}
fi
L=/appz/log/lsyncd_watch.log
touch $L
echo $(date)" =========================================================" >> $L
nc -zvw3 $FILESYNC_REMOTE_IP 12000
if [[ $? -eq 0 ]];then
        supervisorctl status lsyncd | awk -F " " '{print $2}' |grep -iq "RUNNING"
        if [[ $? -eq 0 ]];then
            echo "INFO :::: "$(date)"Lsyncd is  syncing properly " | tee -a $L
        else
            supervisorctl start lsyncd
            if [[ $? -eq 0 ]];then
                echo "INFO :::: "$(date)" Lsyncd is RUNNNING..." | tee -a $L
            else
                echo "ERROR :::: "$(date)" Lsyncd is NOT RUNNING RESTARTING Lsyncd..." | tee -a $L
                supervisorctl restart lsyncd
            fi
        fi
else
        supervisorctl status lsyncd | awk -F " " '{print $2}' |grep -iq "RUNNING"
        if [[ $? -ne 0 ]];then
            echo "INFO :::: "$(date)"Lsyncd stopped syncing " | tee -a $L
        else
            supervisorctl stop lsyncd
            if [[ $? -eq 0 ]];then
                echo "INFO :::: "$(date)" Lsyncd is STOPPED..." | tee -a $L
            else
                echo "ERROR :::: "$(date)" Lsyncd is STOPPING..." | tee -a $L
            fi
        fi
fi
