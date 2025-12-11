 #!/bin/bash
sudo docker ps -a --filter "exited=0" | grep -v CONT | awk '{print $1}' | xargs --no-run-if-empty sudo docker rm
sudo docker images --no-trunc | grep '<none>' | awk '{ print $3 }' | xargs -r sudo docker rmi