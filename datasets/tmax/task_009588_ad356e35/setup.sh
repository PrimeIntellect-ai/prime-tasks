#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/features_a.csv
id,f1
1,4
2,5
3,2
4,10
5,7
6,2
7,3
EOF

    cat << 'EOF' > /home/user/data/features_b.csv
id,f2
3,8
1,2
4,1
5,0
2,5
6,3
7,1
EOF

    chmod -R 777 /home/user
