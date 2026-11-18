#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
1,the quick brown fox
2,jumps over the lazy dog
invalid,this should be ignored
3,a b c d e f g
4,data engineering is fun
EOF

    chmod -R 777 /home/user
