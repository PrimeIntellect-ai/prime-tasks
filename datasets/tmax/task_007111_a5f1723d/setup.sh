#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/system_metrics.csv
timestamp,cpu,mem,net_in,net_out
1000025,20.0,4000.0,100.0,50.0
1000045,22.0,4000.0,110.0,50.0
1000085,25.0,4100.0,120.0,60.0
1000150,95.0,4100.0,800.0,60.0
1000310,20.0,4000.0,100.0,50.0
EOF

    chmod -R 777 /home/user
