#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/logins.csv
u101,12,2
u102,4,10
u103,-1,5
u104,8,0
u105,not_a_num,3
u106,3,14
u107,25,1
u108,1,empty
EOF

    cat << 'EOF' > /home/user/subs.csv
u101,premium
u102,basic
u104,premium
u106,basic
u107,enterprise
u108,basic
u109,free
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
