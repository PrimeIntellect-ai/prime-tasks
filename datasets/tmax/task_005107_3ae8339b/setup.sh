#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest pandas numpy

useradd -m -s /bin/bash user || true

mkdir -p /home/user

cat << 'EOF' > /home/user/weights.csv
feature,weight
f1,2.5
f2,-1.5
bias,1.0
EOF

cat << 'EOF' > /home/user/data.csv
id,f1,f2
1,2.0,1.0
2,,4.0
3,15.0,-2.0
4,-5.0,20.0
5,0.0,0.0
6,-12.0,-12.0
EOF

chmod -R 777 /home/user
