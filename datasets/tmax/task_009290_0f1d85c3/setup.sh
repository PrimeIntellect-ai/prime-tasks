#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_telemetry.csv
1002,10.0
1008,12.0
1010,200.0
1015,-60.0
1021,15.0
1021,17.0
1049,26.0
1050,30.0
EOF

    chmod -R 777 /home/user
