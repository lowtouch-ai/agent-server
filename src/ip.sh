 #!/bin/bash
source ../init.sh
echo "Container IP: "$(sudo docker inspect -f '{{.NetworkSettings.IPAddress}}' $CONTAINER)
