#!/bin/bash
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
usedper=$(free -m | grep -i mem |awk '{print $3/$2 *100}')
int=${usedper/.*}
echo $int
if [ $(echo "$usedper < 80" |bc) -eq "1" ]; then
        check="OK"
elif [ $(echo  "$usedper > 80" |bc) -eq "1" ] && [ $(echo  "$usedper < 90" |bc) -eq "1" ]; then
        check="ABOVE80"
elif [ $(echo  "$usedper > 90" |bc) -eq "1" ]; then
        check="ABOVE90"

fi
total=$(free -m | grep -i mem |awk '{print $2}')
used=$(free -m | grep -i mem |awk '{print $3}')
free=$(free -m | grep -i mem |awk '{print $4}')
shared=$(free -m | grep -i mem |awk '{print $5}')
buff=$(free -m | grep -i mem |awk '{print $6}')
available=$(free -m | grep -i mem |awk '{print $7}')



echo "$LOGDATE APPZ_MEMCHECK:$check total:$total used:$used free:$free shared=$shared buff/cache=$buff available=$available used%:$int " |tee -a  /appz/log/healthcheck_memory.log



used=$(df -h / |grep /| awk '{print $5}')
#dir_array=("/"
#"/var/www/html/wp-content/uploads"
#)
if [ -z "$MOUNT_PATHS" ]; then
    MOUNT_PATHS="/"
fi
IFS=',' read -ra MOUNT_POINT <<< "$(echo -e "${MOUNT_PATHS}" | tr -d '[:space:]')"
for i in "${MOUNT_POINT[@]}"; do
    size=$(df -h "$i" | grep "/" | awk '{print $2}')
    used=$(df -h "$i" | grep "/" | awk '{print $3}')
    avail=$(df -h "$i" | grep "/" | awk '{print $4}')
    userpercent=$(df -h "$i" | grep "/" | awk '{print $5}')
    user_per=${userpercent//%}
    mount=$(df -h "$i" | grep "/" | awk '{print $6}')

    if [ "$(echo "$user_per < 80" | bc)" -eq "1" ]; then
        check="OK"
    elif [ "$(echo "$user_per > 80" | bc)" -eq "1" ] && [ "$(echo "$user_per < 90" | bc)" -eq "1" ]; then
        check="ABOVE80"
    elif [ "$(echo "$user_per > 90" | bc)" -eq "1" ]; then
        check="ABOVE90"
    fi

    echo "$LOGDATE APPZ_DISKCHECK:$check Size:$size Used:$used Avail:$avail Used%:$user_per Path:$i"  |tee -a  /appz/log/healthcheck_disk.log
done

z=$(nproc)
y=`echo "scale=1; $z / 2" | bc`
x=`echo "scale=1; $z / 4" | bc`
#loadaverage=$(uptime|awk -F '[, ]*' '{print $11, $12, $13}')
loadaverage=$(uptime|awk '{print $10, $11, $12}')
declare -a var=(`uptime | awk '{print $10+0}'` `uptime | awk '{print $11+0}'` `uptime | awk '{print $12+0}'`)
#var=( 3 .3 .7)
for  i  in ${var[@]}
do
        max=${var[0]}
        for n in "${var[@]}"
        do
                if [ $(echo "$n > $max"|bc) -eq "1" ]; then
                        max=$n
                fi
        done
        if [ $(echo "$max >= $z" |bc) -eq "1" ]; then
                check="CRITICAL"
        elif [ $(echo "$max >= $y" |bc) -eq "1" ] && [ $(echo "$max < $z" |bc) -eq "1" ]; then
                check="HIGH"
        elif [ $(echo "$max >= $x" |bc) == "1" ] && [ $(echo "$max < $y" |bc) == "1" ] ; then
                check="MEDIUM"
        else
                check="LOW"
        fi
done


echo "$LOGDATE APPZ_LOADCHECK:$check  load average:${var[@]}" | tee -a /appz/log/healthcheck_load.log






