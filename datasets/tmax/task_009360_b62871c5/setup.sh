#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user/pipeline

    cat << 'EOF' > /home/user/data.csv
F1,F2,F3,F4,Target
1.0,2.5,2.0,5.0,0.0
2.0,8.1,4.0,4.0,1.0
3.0,3.2,6.0,3.0,0.0
4.0,9.5,8.0,2.0,1.0
5.0,1.2,10.0,1.0,0.0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
