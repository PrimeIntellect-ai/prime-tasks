#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.json
[
  {"user_id": "U1", "username": "alice", "department": "engineering"},
  {"user_id": "U2", "username": "bob", "department": "sales"},
  {"user_id": "U3", "username": "charlie", "department": "hr"}
]
EOF

    cat << 'EOF' > /home/user/raw_logs_utf8.csv
log_id,user_id,timestamp,message
101,U1,2023-10-01T10:00:00Z,"Error: connection timeout"
102,U2,2023-10-01T10:05:00Z,"Failed to load module
Module 'auth' not found
Traceback provided."
101,U1,2023-10-01T10:00:00Z,"Error: connection timeout"
103,U3,2023-10-01T10:10:00Z,"User login successful"
104,U1,2023-10-01T10:15:00Z,"Data loaded enc: café"
EOF

    iconv -f UTF-8 -t ISO-8859-1 /home/user/raw_logs_utf8.csv > /home/user/raw_logs.csv
    rm /home/user/raw_logs_utf8.csv

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
