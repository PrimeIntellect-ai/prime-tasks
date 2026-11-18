#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/campaign_data.csv
date,campaign_id,clicks,conversions
2023-10-01,Alpha,250,22
2023-10-01,Beta,300,32
2023-10-02,Alpha,260,28
2023-10-02,Beta,310,36
2023-10-03,Alpha,240,20
2023-10-03,Beta,290,29
2023-10-04,Alpha,250,25
2023-10-04,Beta,300,33
EOF

    chmod -R 777 /home/user
