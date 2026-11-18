#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/etl
    cat << 'EOF' > /home/user/sensor_data.csv
1.0,2.0,3.0
-1.0,0.5,1.5
2.0,-1.0,0.0
0.0,0.0,5.0
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
