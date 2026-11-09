#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/references.csv
Material,Frequency
Alpha,18.05
Beta,18.24
Gamma,18.40
Delta,18.88
EOF

    chmod -R 777 /home/user
