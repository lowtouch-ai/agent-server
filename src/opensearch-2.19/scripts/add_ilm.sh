#!/bin/bash
if [[ "${ENABLE_ILM:-0}" -eq 1 ]] ; then
 ILM_API_URL="localhost:9200/_ilm/policy/ilm_policy?pretty"
 ILM_CONTENT='{
 "policy": {
    "phases": {
      "hot": {
        "actions": {
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "'"${MIN_AGE_WARM}"'",
        "actions": {
          "set_priority": {
            "priority": 50
          }
        }
      },
      "cold": {
        "min_age": "'"${MIN_AGE_COLD}"'",
        "actions": {
          "freeze": {},
          "set_priority": {
            "priority": 10
          }
        }
      }
    }
  }
 }'
 maxcounter=180
 counter=1
 while [ $counter -le $maxcounter ] > /dev/null 2>&1; do
   STATUS=$(curl -X GET "localhost:9200/_cluster/health?pretty")
   CLUSTER_STATUS=$(echo "$STATUS" | jq -r '.status')
   if [[ "$CLUSTER_STATUS" == "green" ]]; then
           echo "Opensearch Cluster is healthy"
           break
   else
            counter=`expr $counter + 1`
            sleep 1
   fi
 done



 ILM_RESPONSE=$(curl -X PUT "$ILM_API_URL" -H "Content-Type: application/json" -d "$ILM_CONTENT")
 if echo "$ILM_RESPONSE" | jq '.acknowledged' | grep -q "true"; then
   echo "ILM Policy added successfully."
 else
   echo "Failed to add ILM Policy"
 fi

 TEMPLATE_RESPONSE=$(curl -X PUT "localhost:9200/_index_template/my-template1?pretty" -H 'Content-Type: application/json' -d'
 {
  "index_patterns": ["graylog_*"],
  "template": {
    "settings": {
      "index.blocks.write": false,
      "index.lifecycle.name": "ilm_policy",
      "index.max_result_window": '$MAX_RESULT_WINDOW'
    },
    "mappings": {
      "properties": {
        "timestamp": {
          "type": "date",
          "format" : "yyyy-MM-dd HH:mm:ss.SSS"
        }
      }
    }
  }
  }
 ')

 if echo "$TEMPLATE_RESPONSE" | jq '.acknowledged' | grep -q "true"; then
   echo "Template  added successfully."
 else
   echo "Failed to add template"
 fi

else
 echo "ILM Not Configured"
fi

