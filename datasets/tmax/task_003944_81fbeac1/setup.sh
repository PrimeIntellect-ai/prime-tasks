#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest pandas numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_observations.csv
id,a,b
1,0.5,1.0
2,0.1,2.0
3,0.8,0.5
4,0.9,3.1
5,0.25,1.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
