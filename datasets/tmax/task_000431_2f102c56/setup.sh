#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/purchases.csv
user_id,product_id,timestamp
u1,p1,100
u1,p2,101
u1,p2,102
u2,p1,103
u2,p2,104
u3,p2,105
u3,p3,106
u4,p1,107
u4,p2,108
u4,p3,109
u5,p9,110
u6,p9,111
EOF

    chmod 644 /home/user/purchases.csv
    chmod -R 777 /home/user
