#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest scipy numpy pandas

    mkdir -p /home/user
    cat << 'EOF' > /home/user/obs_data.txt
day,1,2,3,4,5
infected,10,25,50,80,110
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
