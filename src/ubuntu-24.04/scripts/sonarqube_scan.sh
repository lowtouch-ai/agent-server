#!/bin/bash
set -eo pipefail

T=$(date +%Y%m%d-%H%M%S)
L=/appz/log/sonar_scan-$T.log

if env |grep "VAULT:" > /dev/null 2>&1
then
   c=1
   mc=180
   while ! curl -k -o /dev/null -s -w "%{http_code}\n" -k $VAULT_ADDR/v1/sys/health|grep "200"> /dev/null 2>&1;do
   echo "waiting for $VAULT_ADDR..."
   sleep 1
   c=`expr $c + 1`
   if [ $c -gt $mc ];then
      echo "FATAL: vault timeout... exiting"
      exit 1
   fi;done
   VAULT_GET_ADDR=$(echo $VAULT_ADDR|awk -F ':' '{print $1":"$2}' |sed 's/https/http/g')
   source <(curl -s $VAULT_GET_ADDR/get_secret.sh)
fi
echo "Displaying all the BUILD ARGUMENTS" | tee -a $L
echo SONARQUBE = $SONARQUBE	| tee -a $L	
echo SONAR_PROJECT_NAME = $SONAR_PROJECT_NAME | tee -a $L
echo SONAR_PROJECT_KEY = $SONAR_PROJECT_KEY | tee -a $L
echo SONAR_HOST_URL = $SONAR_HOST_URL | tee -a $L
ct=`echo -n $SONAR_LOGIN_TOKEN |wc -c` 
count=`expr $ct - 1`
mask=`echo $SONAR_LOGIN_TOKEN |awk 'BEGIN{FS=OFS=""} {for(i=2;i<='$count';i++) $i="*"}1'`
echo SONAR_LOGIN_TOKEN = $mask   | tee -a $L

echo "Checking npm is installed successfully by version check"	| tee -a $L
npm -v
if [ "$?" -eq 0 ]; then
        echo "Confirming that npm is installed and proceeds to next step"	| tee -a $L
else
        echo "Confirming that npm is not installed . .  . Exiting"		| tee -a $L
        exit 0
fi

if [ "${SONARQUBE}" != "" ] && [ "${SONARQUBE}" == "enabled" ]; then
        echo "SONARQUBE SCAN ENABLED" | tee -a $L
        echo "Installing the Sonarqube scanner module" | tee -a $L
        npm install -g sonarqube-scanner
        SONAR_PROPERTIES=./sonar-project.properties

        if [ "${SCAN_LANG}" == "node" ]; then
                echo "sonar.language=js" > $SONAR_PROPERTIES
        elif [ "${SCAN_LANG}" == "python" ]; then
                echo "sonar.language=py" > $SONAR_PROPERTIES
        else
                echo "PROJECT LANGUAGE not defined"
        fi

        echo "sonar.projectKey=$SONAR_PROJECT_KEY" >> $SONAR_PROPERTIES         | tee -a $L
        echo "sonar.projectName=$SONAR_PROJECT_NAME" >> $SONAR_PROPERTIES	| tee -a $L
        echo "sonar.projectVersion=4.5" >> $SONAR_PROPERTIES			| tee -a $L
        echo "sonar.javascript.node.maxspace=8192" >> $SONAR_PROPERTIES		| tee -a $L
        echo "sonar.host.url=$SONAR_HOST_URL" >> $SONAR_PROPERTIES		| tee -a $L
        echo "sonar.sourceEncoding=UTF-8" >> $SONAR_PROPERTIES			| tee -a $L
        echo "sonar.verbose=true" >> $SONAR_PROPERTIES                          | tee -a $L
        echo "sonar.login=$SONAR_LOGIN_TOKEN" >> $SONAR_PROPERTIES              | tee -a $L
	echo "sonar.sources=${SONAR_SOURCES:-.}" >> $SONAR_PROPERTIES           | tee -a $L

        if [ "${NODE_MODULES}" != "" ]; then
                for i in $(echo $NODE_MODULES | sed "s/,/ /g")
		do
			if [ ! $(npm list -s | grep $i > /dev/null 2>&1) ]; then

                                echo " Already installed $i in the server, doesn't require to install it again "
                        else
                                npm install -g $i
                                npm link $i
                                sleep 2
                        fi
		done
	fi

	if [ ! -z "$SONAR_EXCLUSIONS" ]; then
                echo "sonar.exclusions=$SONAR_EXCLUSIONS" >> $SONAR_PROPERTIES                          | tee -a $L
        else
                echo "No files to exclude"
        fi
	echo "SonarQube scan started" | tee -a $L
        sonar-scanner -X -D $SONAR_PROPERTIES | tee -a $L
        if [ "$?" -eq 0 ]; then
               echo " SonarQube scan Completed . . . . . Removing up modules, packages required for the scan" | tee -a $L
               npm uninstall -D sonarqube-scanner && npm uninstall -g sonarqube-scanner
               rm $SONAR_PROPERTIES
       else
	       echo " SOME ERRORS ENCOUNTERED WHILE SCANNING WITH SONARQUBE, EXITING . . . . . "
	       exit 1
       fi

else
	echo "Warning: Sonarqube scan is Disabled, Proceeding without Sonar scan..."		| tee -a $L
fi
exec "$@"
