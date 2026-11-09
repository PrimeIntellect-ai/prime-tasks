#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/raw_data.csv
ID,X1,X2,Y
1,12,2,0
2,,3,100
3,14,1,0
4,18,2,100
5,10,1,0
6,,4,100
7,20,2,100
8,15,3,100
9,11,1,0
10,25,2,100
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
