#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas networkx

    mkdir -p /home/user/audit_data
    cat << 'EOF' > /home/user/audit_data/locks.csv
transaction_id,resource_id,status,timestamp
T1,R1,GRANTED,1000
T1,R2,WAITING,1005
T2,R2,GRANTED,1001
T2,R1,WAITING,1006
T3,R3,GRANTED,1002
T3,R4,WAITING,1007
T4,R4,GRANTED,1003
T4,R5,WAITING,1008
T5,R5,GRANTED,1004
T5,R3,WAITING,1009
T5,R6,WAITING,1010
T6,R6,GRANTED,1011
T6,R7,WAITING,1012
T7,R7,GRANTED,1013
T7,R5,WAITING,1014
T8,R8,GRANTED,1015
T9,R8,WAITING,1016
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
