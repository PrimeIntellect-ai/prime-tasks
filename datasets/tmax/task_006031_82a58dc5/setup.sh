#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/network.txt
0 1
1 2
2 0
2 3
3 4
4 5
5 3
5 6
6 7
7 5
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
