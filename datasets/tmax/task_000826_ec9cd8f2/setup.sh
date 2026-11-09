#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/stream1.csv
2023-10-25T14:32:45Z,S1,battery_low
2023-10-25T14:32:59Z,S1,battery_low
2023-10-25T14:35:10Z,S2,temp_high
EOF

    cat << 'EOF' > /home/user/data/stream2.csv
2023-10-25T14:32:15Z,S1,battery_low
2023-10-25T14:35:12Z,S2,temp_high
2023-10-25T14:40:05Z,S1,rebooting
EOF

    chown -R user:user /home/user/data
    chmod -R 777 /home/user
