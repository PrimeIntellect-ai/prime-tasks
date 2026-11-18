#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/nodes.csv
id,year
p1,2015
p2,2018
p3,2019
p4,2020
p5,2021
p6,2018
p7,2022
EOF

cat << 'EOF' > /home/user/edges.csv
source,target
p1,p2
p2,p3
p3,p2
p4,p2
p5,p2
p6,p3
p7,p4
p7,p5
p4,p5
p3,p5
p2,p7
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
