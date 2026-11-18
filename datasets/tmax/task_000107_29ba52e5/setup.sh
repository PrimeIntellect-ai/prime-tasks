#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
1,1.5,2.0
1,2.5,1.0
2,0.5,0.5
2,1.2,1.8
3,3.0,0.2
3,0.1,2.0
EOF

    chmod -R 777 /home/user
