#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ wget
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/experiments.csv
experiment_id,accuracy,epoch_count,status
EXP_001,0.95,100,SUCCESS
EXP_002,1.05,50,SUCCESS
TEST_003,0.88,20,FAILED
EXP_004,0.92,-5,SUCCESS
EXP_005,0.80,10,FAILED
EXP_006,invalid,10,SUCCESS
EXP_007,0.85,30,UNKNOWN
EXP_008,0.91,40,SUCCESS
EOF

    chmod -R 777 /home/user
