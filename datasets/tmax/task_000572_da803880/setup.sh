#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/raw_data.csv
id,val1,val2
1,5,10
2,-999,20
3,8,-999
4,15,5
5,2,2
6,-999,-999
7,12,12
8,6,3
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
