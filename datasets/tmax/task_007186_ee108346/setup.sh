#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/campaign_data.csv
date,variant,visitors,conversions
2023-10-01,A,500,50
2023-10-01,B,600,90
2023-10-02,A,-100,0
2023-10-02,A,500,70
2023-10-02,B,450,70
2023-10-03,B,0,0
2023-10-03,A,200,-5
EOF

    chmod -R 777 /home/user
