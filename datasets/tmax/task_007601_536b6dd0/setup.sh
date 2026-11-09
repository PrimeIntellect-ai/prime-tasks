#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.csv
metric_A,metric_B,metric_C
1.0,2.0,1.0
2.0,4.0,0.0
3.0,NA,1.0
4.0,8.0,0.0
5.0,10.0,1.0
EOF

    chmod -R 777 /home/user
