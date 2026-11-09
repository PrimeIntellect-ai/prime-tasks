#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/hyperparameters.csv
exp_id,param_a,param_b,param_c
1,10,20,30
2,12,20,30
3,10,25,30
4,15,20,30
5,10,20,35
6,11,21,31
7,20,30,40
8,10,20,29
EOF

    cat << 'EOF' > /home/user/results.csv
exp_id,accuracy
1,80.0
2,82.0
3,85.0
4,78.0
5,NaN
6,81.0
7,NaN
8,79.0
EOF

    chmod -R 777 /home/user
