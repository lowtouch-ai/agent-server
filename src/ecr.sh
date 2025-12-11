#!/bin/bash
parent=`dirname $PWD`
project=`basename $PWD` 
PROJECT=`basename $PWD | tr '-' ':'`
repo_name=`basename $PWD |  cut -d"-" -f1`
registry_url=$1
tag=":$3"
tags="$3"
REGION="$2"
IMAGE=appz/$PROJECT
DEFAULT="y"
output=$(aws ecr describe-repositories --region $REGION --repository-names $repo_name 2>&1)
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $registry_url
echo "aws ecr create-repository --repository-name $repo_name --image-scanning-configuration scanOnPush=true"
read -p "Are you sure you want to continue? (y/N) " prompt
prompt="${prompt:-${DEFAULT}}"
if [[ $prompt == "y" ]] &&  output=$(aws ecr describe-repositories --region $REGION --repository-names $repo_name 2>&1)|| [ $? -ne 0 ] && echo ${output} | grep -q RepositoryNotFoundException;
then  
  aws ecr create-repository --repository-name $repo_name --region $REGION --image-scanning-configuration scanOnPush=true
else
  >&2 echo ${output}
fi  
echo "docker tag $IMAGE $registry_url/${repo_name}${tag}"
read -p "Are you sure you want to continue? (y/N) " prompt
prompt="${prompt:-${DEFAULT}}"
if [[ $prompt == "y" ]]
then
  docker tag $IMAGE $registry_url/${repo_name}${tag}
else
  exit 0
fi
echo "docker push $registry_url/${repo_name}${tag}"
read -p "Are you sure you want to continue? (y/N) " prompt
prompt="${prompt:-${DEFAULT}}"
if [[ $prompt == "y" ]]
then
  docker push $registry_url/${repo_name}${tag}
else
  exit 0
fi
echo "aws ecr describe-image-scan-findings --repository-name $repo_name --image-id imageTag=$tags --region $REGION --output json"
read -p "Are you sure you want to continue? (y/N) " prompt
prompt="${prompt:-${DEFAULT}}"
if [[ $prompt == "y" ]]
then
  echo "Please wait until the ECR scan is complete"
  sleep 60s
  [ -e $project.json ] && rm $project.json
  aws ecr describe-image-scan-findings --repository-name $repo_name --image-id imageTag=$tags --region $REGION --output json | tee -a $project.json
else
  exit 0
fi
/usr/bin/python3 "$parent"/ecr.py


