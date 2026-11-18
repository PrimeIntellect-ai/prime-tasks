#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
1,0.0,0.0
2,3.0,4.0
3,-1.0,-1.0
EOF

    cat << 'EOF' > /home/user/items.csv
101,1.0,1.0
102,0.0,5.0
103,-2.0,-2.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
