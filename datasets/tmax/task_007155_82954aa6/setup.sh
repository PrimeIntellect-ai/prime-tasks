#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/locks.csv
timestamp,trx_id,resource_id,lock_mode,state
1,T01,RES_A,EXCLUSIVE,GRANTED
2,T02,RES_B,EXCLUSIVE,GRANTED
3,T03,RES_C,SHARED,GRANTED
4,T04,RES_D,EXCLUSIVE,GRANTED
5,T05,RES_E,SHARED,GRANTED
6,T06,RES_A,SHARED,WAITING
7,T01,RES_B,EXCLUSIVE,WAITING
8,T02,RES_C,EXCLUSIVE,WAITING
9,T03,RES_D,EXCLUSIVE,WAITING
10,T04,RES_A,SHARED,WAITING
11,T05,RES_F,EXCLUSIVE,GRANTED
12,T06,RES_F,SHARED,WAITING
EOF

    cat << 'EOF' > /home/user/trx_users.json
{
  "T01": {"user_id": "U_ALICE"},
  "T02": {"user_id": "U_BOB"},
  "T03": {"user_id": "U_CHARLIE"},
  "T04": {"user_id": "U_DIANA"},
  "T05": {"user_id": "U_EVE"},
  "T06": {"user_id": "U_FRANK"}
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
