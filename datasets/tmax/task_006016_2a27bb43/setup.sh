#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/mutations.tsv
Generation	Mutations
1	10
2	14
3	21
4	32
5	48
6	72
7	105
8	158
9	230
10	340
EOF

    chmod -R 777 /home/user
