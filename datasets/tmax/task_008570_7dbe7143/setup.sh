#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/server_logs.txt
[2024-03-15 08:14] U101 CONNECT IP:192.168.1.1
[2024-03-15 08:45] U102 DISCONNECT IP:10.0.0.5
[2024-03-15 08:50] U101 QUERY DB:SELECT_USERS
[2024-03-15 09:15] U999 INVALID NOTHING:HERE
[2024-03-15 10:05] U103 CONNECT IP:172.16.0.2
[2024-03-15 10:30] U101 ERROR TIMEOUT
EOF

    cat << 'EOF' > /home/user/data/users.csv
user_id,tier
U101,premium
U102,basic
U103,premium
U104,enterprise
EOF

    chmod -R 777 /home/user
