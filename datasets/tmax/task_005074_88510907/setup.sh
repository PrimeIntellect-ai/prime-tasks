#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/data/raw_vectors.csv
ID,VectorData
1,"[3.0, 4.0, 12.0]"
2,"[1.0, 1.0]"
3,"[0.0, \u03c0, 4.0]"
4,"corrupted_string_data"
5,"[-1.0, -1.0, -1.0, -1.0]"
6,"[2.0, 2.0, 2.0, \u03c0, 0.0]"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
