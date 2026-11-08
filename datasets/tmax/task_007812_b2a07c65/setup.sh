#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/clicks.csv
campaign_id,platform,clicks
C001,Google,150
C002,Facebook,80
C003,Google,1200
C004,Twitter,450
C005,Facebook,95
C006,LinkedIn,320
EOF

    cat << 'EOF' > /home/user/conversions.csv
campaign_id,conversions
C001,15
C002,5
C003,180
C004,22
C005,8
C006,45
EOF

    chmod -R 777 /home/user
