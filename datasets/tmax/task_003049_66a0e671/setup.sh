#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/observations.csv
lambda,x
1.0,0.435
2.0,0.697
3.0,0.893
4.0,1.052
5.0,1.187
6.0,1.305
7.0,1.411
8.0,1.506
9.0,1.701
10.0,1.621
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
