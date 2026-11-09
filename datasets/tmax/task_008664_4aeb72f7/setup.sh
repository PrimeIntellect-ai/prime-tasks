#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/raw_sensors.log
1690000000,temp_01,42.1
1690000001,temp_02,46.0
1690000002,press_01,100.5
1690000003,temp_01,44.9
1690000004,temp_03,45.6
EOF

    chmod -R 777 /home/user
