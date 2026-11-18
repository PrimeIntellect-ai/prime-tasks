#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
id,f1,f2,f3
1,10.0,20.0,30.0
2,40.0,,60.0
3,,80.0,90.0
4,12.0,14.0,
5,,,
EOF

    cat << 'EOF' > /home/user/weights.txt
0.5,0.2,0.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
