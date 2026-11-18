#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/locks.csv
tx_id,resource_id,lock_state
10,R1,HELD
20,R2,HELD
30,R3,HELD
40,R4,HELD
50,R5,HELD
60,R6,HELD
10,R2,WAITING
20,R3,WAITING
30,R1,WAITING
40,R5,WAITING
50,R4,WAITING
70,R6,WAITING
80,R7,WAITING
15,R1,WAITING
EOF

    chmod -R 777 /home/user
