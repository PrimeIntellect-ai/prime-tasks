#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential libsqlite3-dev
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/data/parts.csv
part_id,parent_id,qty_per_parent,unit_cost
1,NULL,1,0.0
2,1,2,10.0
3,1,1,5.0
4,2,4,2.0
5,4,2,1.5
6,3,5,1.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data /home/user/workspace
    chmod -R 777 /home/user
