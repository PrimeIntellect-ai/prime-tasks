#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/ratings.csv
1,5.0,3.0,4.0,4.0,2.0
2,3.0,1.0,2.0,3.0,3.0
3,4.0,3.0,4.0,5.0,1.0
4,5.0,2.0,4.0,4.0,1.0
5,1.0,5.0,2.0,1.0,4.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
