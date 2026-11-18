#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_metrics.csv
ID,CPU,Memory,DiskIO,Latency
1,45.0,60.0,120.0,15.2
2,85.0,90.0,80.0,45.5
3,20.0,30.0,200.0,5.0
4,95.0,88.0,50.0,80.1
5,50.0,50.0,150.0,20.0
6,70.0,75.0,100.0,35.4
7,10.0,20.0,250.0,2.1
8,65.0,70.0,110.0,28.9
9,90.0,85.0,60.0,65.2
10,35.0,40.0,180.0,10.5
EOF

    chmod -R 777 /home/user
