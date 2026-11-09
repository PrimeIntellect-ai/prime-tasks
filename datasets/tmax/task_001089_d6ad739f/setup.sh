#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/pipeline
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/sourceA.csv
id,f1,f2,f3
1,10.0,20.0,30.0
2,15.0,25.0,35.0
3,20.0,30.0,40.0
5,10.0,10.0,10.0
EOF

    cat << 'EOF' > /home/user/data/sourceB.csv
id,f4,f5
2,40.0,50.0
3,45.0,55.0
4,50.0,60.0
5,20.0,20.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
