#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/graph_dump.csv
src_id,src_type,dst_id,dst_type,latency_ms
Gateway_Alpha,Gateway,App_1,App,20
Gateway_Alpha,Gateway,App_2,App,50
App_1,App,Cache_1,Cache,10
Cache_1,Cache,DB_Omega,DB,15
App_1,App,DB_Omega,DB,40
App_2,App,DB_Omega,DB,10
App_2,App,Auth_1,Auth,5
Auth_1,Auth,DB_Omega,DB,60
EOF

chmod -R 777 /home/user
