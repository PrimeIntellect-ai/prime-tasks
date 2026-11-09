#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/perf_data.csv
CPU,Mem,IO,Latency
10,20,5,69
50,10,2,145
20,40,10,138
30,30,30,231
80,5,1,210
EOF

    chmod -R 777 /home/user
