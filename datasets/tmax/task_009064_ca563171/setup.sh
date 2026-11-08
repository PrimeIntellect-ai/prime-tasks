#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/etl_dependencies.csv
job_A,job_B
job_B,job_C
job_C,job_D
job_D,job_B
job_E,job_F
job_F,job_G
job_G,job_H
job_H,job_F
job_X,job_Y
job_Y,job_Z
job_Z,job_W
job_M,job_N
job_N,job_O
job_O,job_P
job_P,job_M
job_I,job_J
EOF

    chmod -R 777 /home/user
