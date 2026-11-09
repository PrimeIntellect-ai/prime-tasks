#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_data.csv
date,entity_id,text,daily_score
2023-10-01,A,Café!,10.0
2023-10-02,A,Good😊,15.0
2023-10-03,A,Привет,20.0
2023-10-04,A,Olé,10.0
2023-10-01,B,No nonascii,5.0
2023-10-02,B,test,5.0
2023-10-03,B,test,11.0
EOF

    chmod -R 777 /home/user
