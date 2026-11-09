#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/fileA.txt
id,name,city
1,Alpha,New York
2,Beta,Boston
3,Gamma,Chicago
4,Delta,Seattle
5,Echo,Austin
6,Zeta,Denver
EOF

    cat << 'EOF' > /home/user/data/fileB.txt
src,dst,cost
1,2,30
1,3,50
2,4,40
3,4,60
3,5,20
4,6,10
5,6,15
EOF

    chmod -R 777 /home/user
