#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
Hour,StationA_Temp,StationA_Status,StationB_Temp,StationB_Status
8,15.5,En_línea,22.1,正常
11,,Error_🔥,23.0,警告
14,16.2,En_línea,,正常
EOF

    chmod -R 777 /home/user
