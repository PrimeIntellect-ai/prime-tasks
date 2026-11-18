#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/locks.csv
tx_id,resource_id,status,timestamp
T1,R1,GRANTED,1
T2,R2,GRANTED,2
T1,R2,WAITING,3
T2,R1,WAITING,4
T3,R3,GRANTED,5
T4,R4,GRANTED,6
T3,R4,WAITING,7
T4,R3,WAITING,8
T5,R5,GRANTED,9
T6,R6,GRANTED,10
T5,R6,WAITING,11
T7,R7,GRANTED,12
T8,R8,GRANTED,13
T8,R7,WAITING,14
T7,R8,WAITING,15
T9,R9,GRANTED,16
T10,R10,GRANTED,17
T9,R10,WAITING,18
T11,R11,GRANTED,19
T10,R11,WAITING,20
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
