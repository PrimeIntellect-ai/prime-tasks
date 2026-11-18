#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/telemetry.csv
timestamp,server_id,cpu_usage,ram_usage,status,log_message
1,S1,45.5,60.2,OK,Normal operation
2,S2,,55.0,OK,Missing cpu
3,S1,105.0,90.0,CRASH,Outlier cpu
4,S3,90.5,88.0,CRASH,Database connection timeout occurred
5,S2,88.0,85.0,CRASH,Connection to database failed
6,S1,86.0,80.0,OK,High load but stable
7,S3,95.0,92.0,CRASH,Database timeout
8,S4,-5.0,10.0,OK,Sensor error
9,S2,50.0,55.0,OK,System normal
10,S1,92.0,89.0,OK,Spike detected
EOF

    chown -R user:user /home/user/data
    chown -R user:user /home/user/output
    chmod -R 777 /home/user
