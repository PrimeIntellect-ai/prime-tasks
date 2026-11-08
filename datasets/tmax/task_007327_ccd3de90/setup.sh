#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas
pip3 install torch --index-url https://download.pytorch.org/whl/cpu

mkdir -p /home/user
cat << 'EOF' > /home/user/data.csv
x,y
-3.0,-4.5
-2.0,-4.8
-1.0,-2.5
0.0,1.1
1.0,4.6
2.0,6.9
3.0,7.6
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
