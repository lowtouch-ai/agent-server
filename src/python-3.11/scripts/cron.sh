#!/bin/bash
env >> /appz/scripts/.env
sed -i -e 's/^/export /' /appz/scripts/.env
PIDNO=$(pidof cron)

if [ -z $PIDNO ]; then
	
	/usr/sbin/cron -f
else
	pkill -9 cron
	/usr/sbin/cron -f
fi
