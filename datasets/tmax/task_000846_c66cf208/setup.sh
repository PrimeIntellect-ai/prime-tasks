#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx apache2-utils curl
    pip3 install pytest rdflib networkx fastapi uvicorn requests

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/cities.csv
city_id,name,region
1,Alpha,North
2,Beta,South
3,Gamma,East
4,Delta,West
EOF

    cat << 'EOF' > /home/user/data/connections.csv
from_id,to_id,cost
1,2,10
2,3,15
1,4,50
3,4,10
2,4,30
EOF

    chmod -R 777 /home/user
