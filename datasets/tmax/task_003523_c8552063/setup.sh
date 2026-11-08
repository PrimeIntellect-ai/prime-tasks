#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libgsl-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
x,y
1.0,2.1
2.0,3.9
3.0,6.2
4.0,8.0
5.0,10.1
EOF

    chmod -R 777 /home/user
