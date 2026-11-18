#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/services.csv
id,base_cost
S1,50
S2,120
S3,30
S4,200
S5,10
S6,80
S7,45
S8,15
EOF

    cat << 'EOF' > /home/user/dependencies.csv
service_id,depends_on_id
S1,S2
S1,S3
S2,S4
S2,S5
S3,S5
S3,S6
S6,S7
S6,S8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
