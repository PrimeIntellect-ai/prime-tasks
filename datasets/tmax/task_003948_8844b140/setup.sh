#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc time coreutils
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/users.csv
1,alice@example.com,hello
2,bob_no_at_domain.com,skip this
3,charlie@example.com,test
4,david@example.com,world
EOF

    cat << 'EOF' > /home/user/data/legacy_hashes.csv
1,100
3,200
4,300
5,400
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
