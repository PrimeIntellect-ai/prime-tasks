#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/locks.csv
tx_id,holds_resource,waits_for_resource
T1,R1,R2
T2,R2,R3
T3,R3,R1
T4,R4,
T5,,R4
T6,R6,R7
T7,R7,R6
T7,R8,
T8,,R8
T1,R9,R10
T9,R10,R9
EOF

    chmod -R 777 /home/user
