#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/customers.csv
id,age,status
1,25,ACTIVE
2,17,ACTIVE
3,30,UNKNOWN
4,45,INACTIVE
5,NaN,ACTIVE
6,22,ACTIVE
invalid,20,ACTIVE
8,28,ACTIVE
EOF

    cat << 'EOF' > /home/user/logs.jsonl
{"user_id": 1, "text": "hello world"}
{"user_id": 2, "text": "not 18"}
{"user_id": 4, "text": "inactive user log text"}
{"user_id": 6, "text": "this has exactly five tokens"}
{"user_id": 7, "text": "no matching customer"}
{"user_id": 8, "text": "   leading and trailing spaces count   "}
EOF

    chmod -R 777 /home/user
