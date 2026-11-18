#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/data.csv
1,3.1
2,4.9
3,7.2
4,8.9
5,11.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
