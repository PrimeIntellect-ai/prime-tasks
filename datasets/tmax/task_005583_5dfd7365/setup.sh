#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_sensor_data.txt
2 100 45.0
1 105 10.0
2 101 46.0
1 100 12.0
1 110 35.0
2 102 80.0
3 500 10.0
3 501 15.0
EOF

    chmod -R 777 /home/user
