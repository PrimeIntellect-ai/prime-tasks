#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sys_config.log
1 MAX_MEM 100
1 CPU_CORES 4
2 MAX_MEM 110
4 MAX_MEM 110
5 MAX_MEM 200
6 MAX_MEM 190
7 MAX_MEM 190
8 MAX_MEM 220
EOF

    chmod -R 777 /home/user
