#!/bin/bash


PIDNO=$(pidof cron)

if [ -z $PIDNO ]; then
	
	/usr/sbin/cron -f
else
	pkill -9 cron
	/usr/sbin/cron -f
fi
