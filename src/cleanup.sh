 #!/bin/bash 
source ../init.sh

sudo docker kill $CONTAINER
sudo docker rm $CONTAINER
 
