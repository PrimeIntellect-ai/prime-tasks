#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev sqlite3
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/wait_for.csv
tx_waiting,tx_holding
1,2
2,3
3,1
4,5
5,6
7,8
8,7
9,10
10,11
11,12
12,13
13,14
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
