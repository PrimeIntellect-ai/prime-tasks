#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/test_cases.json
{
  "case1": [{"cpu_usage": 80}, {"cpu_usage": 40}, {"mem_usage": 500}],
  "case2": [{"cpu_usage": 80}, {"cpu_usage": 80}, {"cpu_usage": 80}],
  "case3": [{"cpu_usage": 20}, {"mem_usage": 2000}],
  "case4": [{"cpu_usage": 30}],
  "case5": [{"cpu_usage": 90}, {"cpu_usage": 90}, {"cpu_usage": 45}, {"mem_usage": 800}]
}
EOF

cat << 'EOF' > /home/user/deploy.machine.raw
STATE START:
  SET attempts = 0
  TRANSITION TO POLL

STATE POLL:
  READ_EVENT
  IF cpu_usage < 50 THEN TRANSITION TO STAGING
  SET attempts = attempts + 1
  IF attempts > 2 THEN TRANSITION TO FAIL
  TRANSITION TO POLL

STATE STAGING:
  READ_EVENT
  IF mem_usage < 1024 THEN TRANSITION TO PROD
  TRANSITION TO FAIL

STATE PROD:
  TRANSITION TO SUCCESS
EOF

python3 -c 'import base64; print(base64.b32encode(open("/home/user/deploy.machine.raw", "rb").read()).decode("utf-8"))' > /home/user/deploy.machine
rm /home/user/deploy.machine.raw

cat << 'EOF' > /home/user/expected_results.json
{
  "case1": "SUCCESS",
  "case2": "FAIL",
  "case3": "FAIL",
  "case4": "TIMEOUT",
  "case5": "SUCCESS"
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
