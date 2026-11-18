#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential cargo rustc
    pip3 install pytest

    mkdir -p /home/user/experiments

    cat << 'EOF' > /home/user/experiments/logs.csv
run_id,x1,x2,x3,y_pred
run_1,0.0,0.0,0.0,1.5
run_2,2.0,0.0,0.0,5.5
run_3,0.0,-1.0,0.0,4.5
run_4,0.0,0.0,4.0,3.5
run_5,1.0,1.0,1.0,999.9
EOF

    cat << 'EOF' > /home/user/experiments/metadata.csv
run_id,status
run_1,SUCCESS
run_2,SUCCESS
run_3,SUCCESS
run_4,SUCCESS
run_5,FAILED
EOF

    cat << 'EOF' > /home/user/experiments/test.csv
test_id,x1,x2,x3
t1,1.0,2.0,2.0
t2,0.0,0.0,0.0
t3,-1.0,-1.0,-2.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
