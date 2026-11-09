#!/bin/bash
read line
IFS=',' read -r tx_id user_id amount timestamp <<< "$line"
risk_score=$(curl -s http://127.0.0.1:5000/api/users/$user_id | jq -r '.risk_score')
limit=$(redis-cli get limit:$user_id)
adjusted=$(echo "$amount * $risk_score" | bc -l)
if $(echo "$adjusted > $limit" | bc -l | grep -q 1); then
    echo "$tx_id,REJECT"
else
    echo "$tx_id,APPROVE"
fi
