#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sensor_data.txt
25.0
33.1
48.2
71.4
115.6
142.3
115.6
71.4
48.2
33.1
25.0
EOF

    chmod -R 777 /home/user
