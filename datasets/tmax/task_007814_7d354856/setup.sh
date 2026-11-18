#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/decay_data.tsv
t	y
1	70.0
2	49.0
3	34.3
4	24.0
5	16.8
6	11.8
7	8.2
8	5.8
9	4.0
10	2.8
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
