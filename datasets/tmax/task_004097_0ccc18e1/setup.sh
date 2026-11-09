#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/clicks.csv
user_id,item_id,category,clicked
u1,i1,A,1
u1,i2,A,0
u2,i1,A,1
u2,i2,B,1
u3,i2,B,1
u3,i3,B,1
EOF

    chmod -R 777 /home/user
