#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    mkdir -p /home/user

    cat << 'EOF' > /home/user/locks.csv
tx_id,resource_id,lock_mode
T1,R1,EXCLUSIVE
T2,R2,SHARED
T3,R3,EXCLUSIVE
T4,R2,SHARED
T5,R4,EXCLUSIVE
T7,R6,EXCLUSIVE
T8,R7,EXCLUSIVE
T9,R8,EXCLUSIVE
EOF

    cat << 'EOF' > /home/user/requests.csv
tx_id,resource_id,requested_mode,timestamp
T1,R2,EXCLUSIVE,1001
T2,R3,EXCLUSIVE,1002
T3,R1,SHARED,1003
T4,R1,SHARED,1004
T6,R4,SHARED,1005
T6,R5,EXCLUSIVE,1006
T7,R7,EXCLUSIVE,1007
T8,R8,SHARED,1008
T9,R6,EXCLUSIVE,1009
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
