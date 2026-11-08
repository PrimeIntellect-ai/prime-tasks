#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/events.csv
id,region,status,amount
1,NA,SUCCESS,100
2,EU,FAILED,50
3,AP,SUCCESS,200
4,NA,SUCCESS,150
5,NA,FAILED,20
6,EU,SUCCESS,300
7,EU,SUCCESS,100
8,AP,FAILED,40
9,NA,SUCCESS,120
10,NA,SUCCESS,80
11,AP,SUCCESS,100
12,EU,SUCCESS,150
13,AP,SUCCESS,50
14,EU,SUCCESS,200
15,NA,FAILED,10
EOF

    chown -R user:user /home/user/data /home/user/output
    chmod -R 777 /home/user
