#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/waits_for.csv
waiter_tx,holder_tx
1,2
2,3
3,4
4,1
5,6
6,7
7,8
8,5
9,10
10,11
11,12
12,9
13,14
14,13
15,16
16,17
17,15
18,19
19,18
EOF

chmod -R 777 /home/user
