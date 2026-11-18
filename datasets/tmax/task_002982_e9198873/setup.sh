#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

apt-get install -y libsqlite3-dev wget curl jq g++

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/transactions.csv
1,U2,1620000001,Clothing,50.00
2,U1,1620000002,Electronics,200.00
3,U1,1620000003,Books,25.50
4,U2,1620000004,Clothing,75.00
5,U1,1620000005,Electronics,150.00
6,U3,1620000006,Home,300.00
7,U1,1620000007,Books,40.00
8,U2,1620000008,Home,120.00
EOF

chmod -R 777 /home/user
