#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /home/user/network_etl

    cat << 'EOF' > /home/user/network_etl/raw_routes.csv
0,1,10
0,2,5
1,2,2
1,3,1
2,3,9
3,4,4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
