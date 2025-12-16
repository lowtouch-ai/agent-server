 #!/bin/bash

T=$(date +%Y%m%d-%H%M%S)
L=/appz/log/cleanup-$(date +%Y%m%d-%H%M%S).log

echo "$T> cleaning up cache files" >> $L
find /appz/cache -type f -mtime +3 -exec rm -fvRd {} \;  >> $L

echo "$T> cleaning up log files" >> $L
find /appz/log -type f -mtime +7 -exec rm -fvRd {} \;  >> $L

echo "$T> cleaning up backup files" >> $L
find /appz/backup -type f -mtime +7 -exec rm -fvRd {} \;  >> $L

echo "$T> cleaning up complete!"  >> $L
