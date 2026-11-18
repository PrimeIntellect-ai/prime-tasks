#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/seq_data.csv
GC,Length
0.35,120
0.41,135
0.45,142
0.50,150
0.55,160
0.60,175
0.65,180
0.70,195
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
