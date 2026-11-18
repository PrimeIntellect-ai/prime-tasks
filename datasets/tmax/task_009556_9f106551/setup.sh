#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensors.csv
1620000000,正常启动,10.0
1620000060,警告: 信号弱,
1620000120,Система OK,14.0
1620000180,En attente,12.0
1620000240,ERROR_SPIKE,100.0
1620000300,استئناف,11.0
EOF

    chmod -R 777 /home/user
