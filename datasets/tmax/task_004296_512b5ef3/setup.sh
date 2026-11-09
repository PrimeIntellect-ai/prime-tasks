#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
user_id,engagement_score,session_duration,bounce_rate
1,0.9,400,0.1
2,,1200,0.8
3,0.4,150,0.5
4,0.8,300,0.2
5,,250,0.3
EOF

    chmod -R 777 /home/user
