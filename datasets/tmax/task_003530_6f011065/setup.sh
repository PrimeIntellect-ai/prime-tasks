#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/server_alpha.csv
date,cache_size,timeout,max_workers
2023-10-01,100,30,4
2023-10-02,100,30,8
2023-10-03,120,45,10
2023-10-04,150,60,16
EOF

    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/data/server_beta.csv
date,cache_size,timeout,max_workers
2023-10-01,105,30,4
2023-10-02,110,30,4
2023-10-03,120,45,10
2023-10-05,150,60,16
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
