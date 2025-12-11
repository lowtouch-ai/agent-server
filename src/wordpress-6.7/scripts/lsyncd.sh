#!/bin/bash

mkdir -p ${ATTACHMENTS_STORAGE_PATH}

if [[ "$FILESYNC_ENABLE" == yes ]]; then
        POD=`echo $HOSTNAME |awk '{print substr($0,length,1)}'`
       	if [[ "$POD" = "0" ]]; then
           FILESYNC_REMOTE_IP="${HOSTNAME%?}1".${HOSTNAME::-2}
	   #FILESYNC_REMOTE_IP="${HOSTNAME%?}1"
        else
           FILESYNC_REMOTE_IP="${HOSTNAME%?}0".${HOSTNAME::-2}
	   #FILESYNC_REMOTE_IP="${HOSTNAME%?}0"

        fi
        cat <<EOF >/etc/lsyncd/lsyncd.conf
        settings {
            statusFile = "/tmp/lsyncd.stat",
            statusInterval = 10,
            maxDelays = 1,
            insist = true,
        }

        sync{
            default.rsync,
            source="${ATTACHMENTS_STORAGE_PATH}",
            target= "filesync@${FILESYNC_REMOTE_IP}::data",
            delete = "running",
            rsync = {
                binary = "/usr/bin/rsync",
                archive = true,
                compress = true,
                verbose = true,
                password_file = "/etc/rsyncd.local",
                _extra = {"--port=12000"}

            }
        }
EOF
/usr/bin/lsyncd -nodaemon -delay 0 /etc/lsyncd/lsyncd.conf 
else
        echo "INFO: FILESYNC_ENABLE not Enabled " | tee -a /appz/log/lsyncd.log
fi
