#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_metrics.csv
server_id,cpu,mem,disk,net,state
SRV_001,45,60,30,80,ACTIVE
SRV_002,-10,50,50,50,ACTIVE
SRV_003,50,50,50,50,ERROR
SRV_004,51,49,50,50,ACTIVE
SRV_005,60,40,60,20,ACTIVE
SRV_006,80,20,10,90,MAINT
SRV_007,49,50,50,50,ACTIVE
SRV_008,12,90,80,90,ACTIVE
EOF

    chmod -R 777 /home/user
