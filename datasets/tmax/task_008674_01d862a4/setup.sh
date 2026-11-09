#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/create_logs.py
import os
with open('/home/user/data/etl_job.log', 'wb') as f:
    f.write(b"1000,1,0,10.0,Started\n")
    f.write(b"1001,1,1,15.0,Retry 1\n")
    f.write(b"1002,1,2,20.0,Retry 2\n")
    f.write(b"1003,1,3,25.0,Retry 3\n")
    f.write(b"1004,2,0,5.0,OK\n")
    f.write(b"1005,3,0,100.0,Fail\xFF\n")
    f.write(b"1006,3,1,110.0,Retry 1\n")
    f.write(b"1007,4,0,10.0,OK\n")
    f.write(b"1008,4,1,10.0,Retry 1\n")
    f.write(b"1009,4,2,10.0,Retry 2\n")
    f.write(b"1010,4,3,10.0,Retry 3\n")
    f.write(b"1011,4,4,10.0,Retry 4\n")
EOF
    python3 /home/user/data/create_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
