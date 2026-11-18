#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ jq
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/tx_locks.csv
timestamp,tx_id,resource_id,status
1000,T1,R1,GRANTED
1001,T2,R2,GRANTED
1002,T1,R2,WAITING
1003,T3,R3,GRANTED
1004,T2,R3,WAITING
1005,T3,R1,WAITING
1006,T4,R4,GRANTED
1007,T5,R5,GRANTED
1008,T4,R5,WAITING
1009,T5,R4,WAITING
1010,T6,R6,GRANTED
1011,T7,R6,WAITING
1012,T8,R7,GRANTED
1013,T9,R8,GRANTED
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
