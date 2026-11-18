#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_temp.csv
id,temperature
1,22.5
2,45.1
3,18.0
4,60.2
5,30.5
EOF

    cat << 'EOF' > /home/user/sensor_vib.csv
id,vibration
1,1.1
2,4.8
3,0.9
4,5.5
5,2.0
EOF

    chmod 644 /home/user/sensor_temp.csv
    chmod 644 /home/user/sensor_vib.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
