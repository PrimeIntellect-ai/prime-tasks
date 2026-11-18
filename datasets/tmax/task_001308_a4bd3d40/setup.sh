#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_data.csv
1,ACTIVE,10.5
-2,ACTIVE,15.0
3,UNKNOWN,20.0
4,INACTIVE,5.5
invalid,ACTIVE,1.0
5,ACTIVE,badfloat
6,ACTIVE,100.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
