#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/inputs.csv
id,e,M
1,0.1,1.0
2,0.9,3.0
3,0.5,1.57079632679
4,0.01,6.28
5,0.75,0.5
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
