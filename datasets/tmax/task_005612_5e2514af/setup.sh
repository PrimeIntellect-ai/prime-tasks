#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/input.csv
id,v1,v2,v3,target
1,0.5,1.2,0.1,2.5
2,1.0,0.0,1.0,3.5
3,2.0,-1.0,0.5,4.0
4,0.0,2.0,1.0,-0.5
5,-1.0,-1.0,-1.0,-2.0
EOF

    cat << 'EOF' > /home/user/weights.csv
1.5,-0.5,2.0
EOF

    chmod -R 777 /home/user
