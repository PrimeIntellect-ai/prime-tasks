#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dependencies.csv
Child,Parent,Processing_Time
Omega,Beta,10
Omega,Gamma,15
Beta,Delta,5
Gamma,Epsilon,20
Delta,Alpha,12
Epsilon,Alpha,8
Zeta,Epsilon,5
Gamma,Delta,8
EOF

    chmod -R 777 /home/user
