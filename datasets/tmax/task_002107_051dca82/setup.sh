#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/server_metrics.csv
id,cpu_usage,memory_usage,status_msg
1,45.5,60.2,System running smoothly
2,95.0,88.1,Warning High Load!
3,105,40,Invalid CPU
4,,50,Missing CPU
5,20.0,30.0,All OK
6,35.5,,Missing Mem
7,50.0,55.0,Normal operation, extra comma
8,80.5,75.0,Load increasing
9,-5,20,Negative CPU
10,60.0,65.0,Check fan speed
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
