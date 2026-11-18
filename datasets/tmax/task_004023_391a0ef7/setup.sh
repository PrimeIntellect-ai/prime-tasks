#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/query_plan.csv
ParentJob,ChildJob,ExecutionCost
START,JOB_A,10
START,JOB_B,50
JOB_A,JOB_B,5
JOB_A,JOB_X,9999
JOB_B,END,20
JOB_A,END,30
START,END,8500
MALFORMED_LINE_NO_COMMAS
JOB_X,END,15
JOB_B,JOB_X,9999
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
