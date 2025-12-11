#!/bin/bash
#
LF_DIR=/appz/log
LF=$LF_DIR/logrotate.log
mkdir -p $LF_DIR
chmod 777 $LF_DIR
touch $LF
chmod 664 $LF
 /usr/sbin/logrotate -v  -s  /var/lib/logrotate/logrotate.status /etc/logrotate.d/logrotate.conf 2>&1 |tee -a $LF
EXITVALUE=$?
if [ $EXITVALUE != 0 ]; then
    /usr/bin/logger -t  logrotate "ALERT exited abnormally with [$EXITVALUE]" |tee -a $LF
fi
exit 0
