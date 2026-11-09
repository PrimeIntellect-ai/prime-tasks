#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ wget curl tar
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/dataset.csv
1.0,2.0,3.0
2.0,NaN,4.0
3.0,4.0,5.0
105.0,6.0,7.0
5.0,8.0,9.0
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
