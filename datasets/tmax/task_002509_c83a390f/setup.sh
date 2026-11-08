#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang build-essential
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/nodes.csv
id,category
N1,frontend
N2,frontend
N3,frontend
N4,backend
N5,backend
N6,backend
N7,auth
N8,auth
EOF

    cat << 'EOF' > /home/user/data/edges.csv
src,dst,weight
N2,N1,15
N3,N1,10
N1,N2,5
N1,N3,50
N4,N5,100
N6,N5,20
N5,N4,50
N5,N6,200
N7,N8,1000
N8,N7,500
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
