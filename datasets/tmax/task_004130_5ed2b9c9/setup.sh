#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/network.csv
source,target,latency,reliability_score,timestamp
S,A,5,0.9,90
S,A,10,0.5,110
S,A,15,0.85,120
S,B,20,0.9,100
A,C,10,0.9,100
B,C,10,0.9,100
C,T,15,0.9,100
B,T,50,0.9,100
A,T,40,0.7,100
A,T,30,0.85,110
A,B,2,0.9,100
A,B,2,0.1,130
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
