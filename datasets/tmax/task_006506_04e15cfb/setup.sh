#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/experiments.csv
exp_id,variant,clicks,views
101,A,45,1000
102,B,60,1050
103,A,50,900
104,C,20,500
105,B,70,1100
106,A,10,200
EOF

    cat << 'EOF' > /home/user/metadata.csv
exp_id,date,category
101,2023-01-01,banner
102,2023-01-01,banner
103,2023-01-02,sidebar
104,2023-01-02,banner
105,2023-01-03,banner
106,2023-01-03,popup
EOF

    chmod -R 777 /home/user
