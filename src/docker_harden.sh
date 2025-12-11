#!/bin/bash 
LOGDATE=`date "+%Y-%m-%d %H:%M:%S,%3N"`
LF_DIR=/tmp
LF=$LF_DIR/docker_bench.log
touch $LF
chmod 664 $LF
docker_count=0
auditd_count=0
os_release="$(awk -F= '/^NAME/{print $2}' /etc/os-release | sed -e 's/^"//' -e 's/"$//')"
if [[ "$os_release" == "Ubuntu" ]]; then
 if [ -x "$(command -v docker)" ]; then
    if [ ! -f /etc/docker/daemon.json ]; then 
        echo $LOGDATE "INFO No daemon config found,creating it" |tee -a $LF
        sudo touch /etc/docker/daemon.json
        sudo chmod 644 /etc/docker/daemon.json
    fi
    echo $LOGDATE "INFO Checking network traffic is restricted between containers on the default bridge" |tee -a $LF
    if sudo docker network ls --quiet | xargs docker network inspect --format '{{ .Name }}: {{ .Options }}' |grep -Fiq com.docker.network.bridge.enable_icc:true 
    then 
      echo $LOGDATE "INFO Network traffic is  not restricted between containers on the default bridge,Restricting it" |tee -a $LF
      if [ -s /etc/docker/daemon.json ]
      then
        if ! cat /etc/docker/daemon.json |grep -Fq  icc
        then
        sudo sed -i '/{/a\  "icc" : false,'  /etc/docker/daemon.json
        echo $LOGDATE "INFO Enabled network restriction between containers on the default bridge" |tee -a $LF
        docker_count=1
        else 
          echo $LOGDATE "INFO network restriction already specified in  daemon config "|tee -a $LF
        fi

      else
        sudo sh -c 'printf "{\n\t\"icc\" : false\n}" > /etc/docker/daemon.json' 
        echo $LOGDATE "INFO Enabled network restriction between containers on the default bridge" |tee -a $LF
        docker_count=1
      fi
    else 
    echo $LOGDATE "INFO Network traffic is already restricted between containers on the default bridge" |tee -a $LF
    fi
    echo $LOGDATE "INFO Checking  the logging level is set to 'info' " |tee -a $LF
    if cat /etc/docker/daemon.json |grep -Fq log-level
    then 
      echo $LOGDATE "INFO logging level is already set to 'info' " |tee -a $LF
    else
      echo $LOGDATE "INFO logging level is not set to 'info'. Setting logging level  to 'info'" |tee -a $LF
      sudo sed -i '/{/a\  "log-level" : "info",'  /etc/docker/daemon.json
      docker_count=1
    fi

    echo $LOGDATE "INFO Checking live restore is enabled "|tee -a $LF
    if [ "$(sudo docker info --format '{{ .LiveRestoreEnabled }}')" == "true" ]; then 
      echo $LOGDATE "INFO live restore is already enabled" |tee -a $LF
    else
        echo $LOGDATE "INFO live restore is not yet enabled.Enabling  live restore" |tee -a $LF
        if ! cat /etc/docker/daemon.json |grep -Fq  live-restore
        then 
            sudo sed -i '/{/a\  "live-restore": true,'  /etc/docker/daemon.json
            echo $LOGDATE "INFO Enabled live restore" |tee -a $LF
            docker_count=1
        else 
            echo $LOGDATE "INFO live restore already specified in  daemon config" |tee -a $LF
        fi
    fi

    echo $LOGDATE "INFO Ensuring  Userland Proxy is Disabled" |tee -a $LF
    if ! cat /etc/docker/daemon.json |grep -Fq  userland-proxy
    then 
      echo $LOGDATE "INFO userland Proxy is not Disabled,Disabling Userland Proxy"|tee -a $LF
      sudo sed -i '/{/a\  "userland-proxy": false,'  /etc/docker/daemon.json 
      echo $LOGDATE "INFO Disabled Userland Proxy"  |tee -a $LF
      docker_count=1
    else 
        echo $LOGDATE "INFO Userland Proxy already specified in  daemon config" |tee -a $LF

    fi

    echo $LOGDATE "INFO Ensuring containers are restricted from acquiring new privileges" |tee -a $LF
    if ! cat /etc/docker/daemon.json |grep -Fq  no-new-privileges
    then 
      echo $LOGDATE "INFO No Restriction found for containers from acquiring new privileges "|tee -a $LF
      sudo sed -i '/{/a\  "no-new-privileges": true,'  /etc/docker/daemon.json 
      echo $LOGDATE "INFO Restricted containers from acquiring new privileges "|tee -a $LF
      docker_count=1
    else 
        echo $LOGDATE "INFO value already specified in  daemon config"|tee -a $LF

    fi
    if [ $docker_count -eq 1 ]; then
     echo $LOGDATE "INFO Restarting docker service"|tee -a $LF
     sudo systemctl restart docker
    
        if [ $? -eq 0 ]; then 
            echo $LOGDATE "INFO Docker service  started successfully"|tee -a $LF
        else 
            echo $LOGDATE "ERROR Couldn't start docker.Please check \"journalctl -ru docker\""|tee -a $LF  
        fi
    fi
 else
     echo $LOGDATE "INFO Docker is not installed please install docker and rerun the script"|tee -a $LF
 fi
 if [ ! -x "$(command -v auditd)" ]; then
     echo $LOGDATE "INFO auditd is not installed installing it"|tee -a $LF
     sudo apt-get install -y auditd
 fi
 echo $LOGDATE "INFO Checking auditd service is running or not"|tee -a $LF
 if ! sudo systemctl is-active --quiet auditd
 then
     echo $LOGDATE "INFO auditd is not running starting it"|tee -a $LF
     sudo systemctl restart  auditd.service
     if [ $? -eq 0 ]; then 
        echo $LOGDATE "INFO service auditd started successfully"|tee -a $LF
     else 
        echo $LOGDATE "ERROR Couldn't start auditd.Please check \"journalctl -ru auditd\""|tee -a $LF
        exit 1
     fi
 else
    echo $LOGDATE "INFO auditd service is running"|tee -a $LF
    echo $LOGDATE "INFO Checking  auditing is configured for the Docker daemon"|tee -a $LF
    if sudo auditctl -l | grep /usr/bin/docker >/dev/null
    then 
      echo $LOGDATE "INFO Auditing is already configured for the Docker daemon"|tee -a $LF
    else 
      if ! sudo cat  /etc/audit/audit.rules |grep -Fq  "/usr/bin/docker"
      then 
        echo $LOGDATE "INFO auditing is not configured for the Docker daemon configuring it "|tee -a $LF
        if ! sudo cat  /etc/audit/rules.d/rule1.rules |grep -Fq  "/usr/bin/docker" 
        then 
           sudo sh -c 'echo "-w /usr/bin/docker -p wa" >> /etc/audit/rules.d/rule1.rules'
           auditd_count=1
        fi
      fi
    fi
    echo $LOGDATE "INFO Checking  auditing is configured Docker files and directories -/var/lib/docker"|tee -a $LF
    if sudo auditctl -l | grep /var/lib/docker >/dev/null
    then 
      echo $LOGDATE "INFO Auditing is already configured for  Docker files and directories -/var/lib/docker "|tee -a $LF
    else 
      if ! sudo cat  /etc/audit/audit.rules |grep -Fq  "/var/lib/docker -k docker"
      then 
        echo $LOGDATE "INFO Auditing is not configured for the Docker files and directories -/var/lib/docker configuring it "|tee -a $LF
        if ! sudo cat  /etc/audit/rules.d/rule1.rules |grep -Fq  "/var/lib/docker -k docker" 
        then 
           sudo sh -c 'echo "-w /var/lib/docker -k docker" >> /etc/audit/rules.d/rule1.rules'
           echo $LOGDATE "INFO Configured  Auditing  for  Docker files and directories -/var/lib/docker "|tee -a $LF
           auditd_count=1
        fi
      fi
    fi 
    
    echo $LOGDATE "INFO Checking  auditing is configured for Docker files and directories - /etc/docker"|tee -a $LF
    if sudo auditctl -l | grep /etc/docker  >/dev/null
    then 
      echo $LOGDATE "INFO Auditing is already configured for Docker files and directories - /etc/docker "|tee -a $LF
    else 
      if ! sudo cat  /etc/audit/audit.rules |grep -Fq  "/etc/docker -k docker"
      then 
        echo $LOGDATE "INFO Auditing is not configured for the Docker files and directories -/etc/docker, configuring it "|tee -a $LF
        if ! sudo cat  /etc/audit/rules.d/rule1.rules |grep -Fq  "/etc/docker -k docker" 
        then 
           sudo sh -c 'echo "-w /etc/docker -k docker " >> /etc/audit/rules.d/rule1.rules'
           echo $LOGDATE "INFO Configured  Auditing  for  Docker files and directories - /etc/docker "|tee -a $LF
           auditd_count=1
        fi
      fi
    fi  
    
    echo $LOGDATE "INFO Checking  auditing is configured for Docker files and directories -  docker.service"|tee -a $LF
    if sudo auditctl -l | grep docker.service  >/dev/null
    then 
      echo $LOGDATE "INFO Auditing is already configured for Docker files and directories -  docker.service "|tee -a $LF
    else 
      if ! sudo cat  /etc/audit/audit.rules |grep -Fq  "/usr/lib/systemd/system/docker.service -k docker"
      then 
        echo $LOGDATE "INFO Auditing is not configured for the Docker files and directories - docker.service, configuring it "|tee -a $LF
        if ! sudo cat  /etc/audit/rules.d/rule1.rules |grep -Fq  "/usr/lib/systemd/system/docker.service -k docker" 
        then 
           sudo sh -c 'echo "-w /usr/lib/systemd/system/docker.service -k docker" >> /etc/audit/rules.d/rule1.rules'|tee -a $LF
           echo $LOGDATE "INFO Configured  Auditing  for  Docker files and directories -  docker.service"
           auditd_count=1
        fi
      fi
    fi  
  
    echo $LOGDATE "INFO Checking  auditing is configured for Docker files and directories -  docker.socket "|tee -a $LF
    if sudo auditctl -l | grep docker.socket >/dev/null
    then 
      echo $LOGDATE "INFO Auditing is already configured for Docker files and directories -  docker.socket  "|tee -a $LF
    else 
      if ! sudo cat  /etc/audit/audit.rules |grep -Fq  "/usr/lib/systemd/system/docker.socket -k docker"
      then 
        echo $LOGDATE "INFO Auditing is not configured for the Docker files and directories - docker.socket , configuring it "|tee -a $LF
        if ! sudo cat  /etc/audit/rules.d/rule1.rules |grep -Fq  "/usr/lib/systemd/system/docker.socket -k docker" 
        then 
           sudo sh -c 'echo "-w /usr/lib/systemd/system/docker.socket -k docker" >> /etc/audit/rules.d/rule1.rules'
           echo $LOGDATE "INFO Configured  Auditing  for  Docker files and directories - docker.socket"|tee -a $LF
           auditd_count=1
        fi
      fi
    fi
   
    echo  $LOGDATE "INFO Checking  auditing is configured for Docker files and directories -/etc/default/docker"|tee -a $LF
    if sudo auditctl -l | grep /etc/default/docker >/dev/null
    then 
      echo $LOGDATE "INFO Auditing is already configured for Docker files and directories - /etc/default/docker"|tee -a $LF
    else 
      if ! sudo cat  /etc/audit/audit.rules |grep -Fq  "/etc/default/docker -k docker"
      then 
        echo $LOGDATE "INFO Auditing is not configured for the Docker files and directories - /etc/default/docker, configuring it "|tee -a $LF
        if ! sudo cat  /etc/audit/rules.d/rule1.rules |grep -Fq  "/etc/default/docker -k docker" 
        then 
           sudo sh -c 'echo "-w /etc/default/docker -k docker" >> /etc/audit/rules.d/rule1.rules'
           echo $LOGDATE "INFO Configured  Auditing  for  Docker files and directories - /etc/default/docker"|tee -a $LF
           auditd_count=1
        fi
      fi
    fi 
  
    echo $LOGDATE "INFO Checking  auditing is configured for Docker files and directories -/etc/docker/daemon.json"|tee -a $LF
    if sudo auditctl -l | grep /etc/docker/daemon.json >/dev/null
    then 
      echo  $LOGDATE "INFO Auditing is already configured for Docker files and directories - /etc/docker/daemon.json"|tee -a $LF
    else 
      if ! sudo cat  /etc/audit/audit.rules |grep -Fq  "/etc/docker/daemon.json -k docker"
      then 
        echo  $LOGDATE "INFO Auditing is not configured for the Docker files and directories - /etc/docker/daemon.json, configuring it "|tee -a $LF
        if ! sudo cat  /etc/audit/rules.d/rule1.rules |grep -Fq  "/etc/docker/daemon.json -k docker" 
        then 
           sudo sh -c 'echo "-w /etc/docker/daemon.json -k docker" >> /etc/audit/rules.d/rule1.rules'
           echo $LOGDATE "INFO Configured  Auditing  for  Docker files and directories - /etc/docker/daemon.json"|tee -a $LF
           auditd_count=1
        fi
      fi
    fi 
 fi
 if [ $auditd_count -eq 1 ]; then
     echo $LOGDATE "INFO Restarting auditd service"|tee -a $LF
     sudo systemctl restart auditd
    
        if [ $? -eq 0 ]; then 
            echo $LOGDATE  "INFO auditd service  started successfully"|tee -a $LF
        else 
            echo $LOGDATE "ERROR Couldn't start auditd.Please check \"journalctl -ru auditd\"" |tee -a $LF 
        fi
    fi            
else 
   echo $LOGDATE "INFO This script is created for Ubuntu platform. Please run it from Ubuntu platform "|tee -a $LF
   exit 1
fi
