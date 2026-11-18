#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip libeigen3-dev g++
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user
cat << 'EOF' > /home/user/experiments.csv
id,v1,v2,v3
exp_001,3.0,4.0,0.0
exp_002,1.0,,1.0
exp_003,NaN,2.0,0.0
exp_004,0.0,0.0,0.0
exp_005,10.0,-10.0,10.0
EOF

chmod -R 777 /home/user
