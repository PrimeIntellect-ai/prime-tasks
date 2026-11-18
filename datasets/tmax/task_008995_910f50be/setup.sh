#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/processed

    cat << 'EOF' > /home/user/raw_data.csv
Hostname,DiskSizeGB,UsedGB,Status
srv1,100,85,Active
srv2,100,50,Active
srv3,200,190,Warning
srv4,500,450,Critical
srv5,50,45,Active
srv6,100,90,Active
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/incoming /home/user/processed /home/user/raw_data.csv
    chmod -R 777 /home/user
