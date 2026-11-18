#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/graph_data.csv
N0,N1,2
N0,N2,5
N0,N3,-10
N1,N3,10
X1,N10,2
N2,N10,A
N2,N3,1
N0,N10
N3,N10,5
N0,N10,50
EOF

chmod -R 777 /home/user
