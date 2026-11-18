#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/input
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/input/features.csv
id,f1,f2,f3,f4,f5
1,1.5,2.0,NaN,4.1,5.0
2,1.6,2.0,0.0,4.1,5.1
3,10.0,10.0,10.0,10.0,10.0
4,1.5,2.0,0.0,4.1,5.0
invalid_id,1.0,2.0,3.0,4.0,5.0
5,10.1,10.0,10.0,10.0,10.0
6,0.0,0.0,0.0,0.0,0.0
7,NaN,NaN,NaN,NaN,NaN
EOF

    chmod -R 777 /home/user
