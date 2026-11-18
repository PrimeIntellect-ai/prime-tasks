#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.csv
id,category,text
1,A,hello world
-1,B,invalid id because negative
2,B,data science in C
3,D,invalid category
4,C,
5,C,the quick brown fox jumps over the lazy dog
0,A,invalid id because zero
6,A,valid record
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
