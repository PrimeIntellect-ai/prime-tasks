#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_metrics.csv
timestamp,cpu,memory,disk
1,50.0,2000,100
2,51.0,2010,102
3,49.0,1990,98
4,-5.0,2005,100
5,50.5,2000,101
6,95.0,2015,99
7,50.2,2000,100
8,49.8,8000,101
9,50.1,2005,100
10,50.0,1995,300
EOF

    chmod -R 777 /home/user
