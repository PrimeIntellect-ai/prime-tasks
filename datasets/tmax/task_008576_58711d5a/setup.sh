#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/etl

    cat << 'EOF' > /home/user/data/raw_logs.csv
Timestamp,Level,Message
2023-10-24 10:00:15,INFO,"System started normally"
2023-10-24 10:00:45,ERROR,"DB connection failed"
2023-10-24 10:01:10,ERROR,"Timeout waiting for lock
Lock held by process 123
Retrying in 5s..."
2023-10-24 10:01:55,WARN,"High memory usage"
2023-10-24 10:04:05,ERROR,"Null pointer exception at line 42"
EOF

    chown -R user:user /home/user/data
    chown -R user:user /home/user/etl

    chmod -R 777 /home/user
