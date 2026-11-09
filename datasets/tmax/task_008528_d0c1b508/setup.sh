#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/network.csv
source_city,target_city,base_cost,delay_factor
Alpha,Beta,10,0.1
Alpha,Gamma,8,0.25
Beta,Delta,12,0.0
Gamma,Delta,5,0.0
Beta,Epsilon,20,0.5
Delta,Epsilon,10,0.1
Epsilon,Zeta,8,0.0
Gamma,Zeta,35,0.1
EOF

    chmod -R 777 /home/user
