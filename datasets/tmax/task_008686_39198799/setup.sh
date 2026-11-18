#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_users.csv
username,department,role
jdoe,finance,admin
asmith,finance,viewer
bwayne,engineering,admin
ckent,engineering,developer
dprince,hr,manager
fcastle,engineering,viewer
EOF

    chmod -R 777 /home/user
