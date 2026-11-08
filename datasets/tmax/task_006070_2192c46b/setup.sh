#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.csv
1700000005,S1,20.0
1700000020,S2,21.0
1700000059,S1,22.0
1700000060,S1,28.0
1700000075,S3,30.0
1700000135,S1,25.0
1700000150,S2,25.0
1700000179,S1,26.5
1700000250,S1,15.0
EOF

    chmod -R 777 /home/user
