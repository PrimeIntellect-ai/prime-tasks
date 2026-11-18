#!/bin/bash
jq -c 'select(.level == "CRITICAL")' | while read -r line; do
  log_id=$(echo "$line" | jq -r '.log_id')
  ip=$(echo "$line" | jq -r '.ip' | sed -E 's/^[0-9]+\.[0-9]+/XXX.XXX/')
  msg=$(echo "$line" | jq -r '.message')
  echo "[INC-8832] ID:${log_id} | IP:${ip} | MSG:${msg}"
done
