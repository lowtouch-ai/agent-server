#!/bin/bash
DR=/appz/log/archive.log

dir=/appz/log/archive
if [[ ! -e $dir ]]; then
    mkdir $dir
elif [[ ! -d $dir ]]; then
    echo "$dir already exists " 1>&2
fi
export TZ="Asia/Kolkata"
YESTERDAY=$(date -d "yesterday" "+%Y-%m-%d")


STATE_FILE="/var/lib/logrotate/logrotate.status"

# Check if the entry is present in the STATE_FILE
if grep -q "\"/appz/log/audit/audit.log\" [0-9]\{4\}-[0-9]\{1,2\}-[0-9]\{1,2\}" "$STATE_FILE"; then
    # Perform the sed operation to replace the date for /appz/log/audit/audit.log with yesterday's date
    #sed -i "s|\"/appz/log/audit/audit.log\" [0-9]\{4\}-[0-9]\{1,2\}-[0-9]\{1,2\}|\"/appz/log/audit/audit.log\" $(date -d "yesterday" +%Y-%m-%d-%H:%M:%S)|g" "$STATE_FILE" 2>&1 | tee -a "$DR"
    sed -i "s|\(\"/appz/log/audit/audit.log\" [0-9]\{4\}-[0-9]\{1,2\}-[0-9]\{1,2\}\)[^\"]*|\1 $(date -d "yesterday" +%Y-%m-%d-%H:%M:%S)|g" "$STATE_FILE" 2>&1 | tee -a "$DR"
else

    echo "\"/appz/log/audit/audit.log\" $(date -d "yesterday" +%Y-%m-%d-%H:%M:%S)" >> "$STATE_FILE"
fi

check_and_add_version_string() {
    if ! grep -q "^logrotate state -- version 2$" "$STATE_FILE"; then
        sed -i '1s/^/logrotate state -- version 2\n/' "$STATE_FILE"
    fi
}
check_and_add_version_string
