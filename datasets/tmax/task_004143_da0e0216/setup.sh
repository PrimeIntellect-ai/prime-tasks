#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/network_edges.csv
source_node,target_node,data_transferred
NodeA,NodeB,50
NodeB,NodeC,20
NodeA,NodeB,30
NodeC,NodeA,100
NodeC,NodeA,50
NodeA,NodeC,10
EOF

chmod -R 777 /home/user
