#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/data.csv
ID,X,Y,Z
101,10,20,30
102,12,18,31
103,12,NA,28
104,13,20,27
105,15,15,25
106,11,18,29
107,12,19,28
108,,19,28
109,12,19,
110,100,200,300
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
