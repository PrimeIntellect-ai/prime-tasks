#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/train.csv
id,reading
1,10.0
2,20.0
3,
4,30.0
EOF

    cat << 'EOF' > /home/user/data/test.csv
id,reading
5,
6,50.0
7,60.0
EOF

    cat << 'EOF' > /home/user/data/meta.csv
id,factor
1,1.5
2,2.0
3,1.0
4,0.5
5,2.0
6,1.0
7,0.5
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
