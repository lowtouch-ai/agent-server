#!/bin/bash
echo "Starting teardown validation..."
TOKEN=$(echo $APPZ_TEARDOWN_TOKEN | tr "-" " ")
TEARDOWN_TOKEN=$(date --date="$TOKEN" +%s)
CURRENT_DATE=$(date -u +%s)
if [ $CURRENT_DATE -lt $TEARDOWN_TOKEN ]
then
  DIFFSECONDS=`expr $TEARDOWN_TOKEN - $CURRENT_DATE`
  DIFFMINUTE=`expr $DIFFSECONDS / 60` 
  echo "time diffence: "${DIFFSECONDS}" seconds == "${DIFFMINUTE}" minutes"
  if [ $DIFFMINUTE -lt 15 ]
  then
    echo "teardown validated! "${DIFFMINUTE}" before token expires"
    APPZ_TEARDOWN_VALIDATED=$APPZ_TEARDOWN_TOKEN
  else 
    echo "teardown not valid! time difference > 15"
    APPZ_TEARDOWN_VALIDATED=null
  fi
else
  echo "teardown not valid! current time > teardown window"
  APPZ_TEARDOWN_VALIDATED=null
fi
