#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy networkx

    mkdir -p /home/user
    cat << 'EOF' > /home/user/network.edges
1 2
2 3
1 3
4 5
EOF
    chmod 644 /home/user/network.edges

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
