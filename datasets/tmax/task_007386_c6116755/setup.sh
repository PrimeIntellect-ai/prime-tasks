#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/user_item.csv
u1,iA
u1,iB
u1,iC
u1,iD
u2,iA
u2,iB
u3,iB
u3,iC
u4,iA
u4,iB
u4,iC
u5,iC
u5,iD
u6,iA
u6,iC
u6,iD
u7,iA
u7,iB
u7,iC
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
