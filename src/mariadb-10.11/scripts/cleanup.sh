 #!/bin/bash
L=/appz/log/cleanup.log

echo "$T> cleaning up cache files" >> $L
find /appz/cache -type f -mtime +3 -exec rm -fv {} \; | tee -a $L

echo "$T> cleaning up backup files" >> $L
find /appz/backup -type f -mtime +7 -exec rm -fv {} \; | tee -a $L

echo "$T> cleaning up complete!"  >> $L

