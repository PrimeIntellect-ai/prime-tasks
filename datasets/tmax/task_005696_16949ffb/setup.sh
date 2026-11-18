#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
1600000000,25.4,26.1
1600000060,25.5,-100.0
1600000120,90.0,26.3
1600000180,25.8,26.5
1600000240,24.0,24.1
EOF

    cat << 'EOF' > /home/user/processed_data.csv
1599999940,1,25.0
1599999940,2,25.5
1600000000,1,25.4
1600000240,1,24.0
1600000240,2,24.1
EOF

    chmod -R 777 /home/user
