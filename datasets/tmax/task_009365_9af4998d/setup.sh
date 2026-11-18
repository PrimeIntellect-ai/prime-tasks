#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/sensor_data

    cat << 'EOF' > /home/user/sensor_data/sensor_1.csv
timestamp,temperature
1,20.0
2,22.0
3,24.0
4,26.0
5,28.0
EOF

    cat << 'EOF' > /home/user/sensor_data/sensor_2.csv
timestamp,temperature
1,10.0
2,15.0
3,20.0
4,25.0
5,25.0
EOF

    cat << 'EOF' > /home/user/sensor_data/sensor_3.csv
timestamp,temperature
1,30.0
2,30.0
3,30.0
4,30.0
5,30.0
EOF

    chmod -R 777 /home/user
