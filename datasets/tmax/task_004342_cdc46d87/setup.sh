#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.csv
1600000000,device_001_1984,10.0
1600000010,device_001_1984,
1600000020,device_001_1984,14.0
1600000030,device_001_1984,11.0
1600000040,device_001_1984,
1600000050,device_001_1984,20.0
1600000060,device_001_1984,
1600000070,device_001_1984,26.0
EOF

    chown user:user /home/user/raw_telemetry.csv
    chmod -R 777 /home/user
