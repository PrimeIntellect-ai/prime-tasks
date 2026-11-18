#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/experiments.csv
experiment_id,temperature,particle_count
exp_B,15.5,10
exp_A,10.0,5
exp_A,12.0,NA
exp_B,16.2,12
exp_A,11.0,6
exp_A,14.0,7
exp_B,14.8,N/A
exp_B,17.0,15
exp_A,10.5,
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
