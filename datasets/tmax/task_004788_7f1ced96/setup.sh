#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/events.csv
event_id,user_id,value
evt_001,1001,45.5
evt_002,,50.0
evt_003,NaN,12.3
evt_004,1002,11.1
evt_005,1.2e4,99.9
evt_006,1003.0,44.4
evt_007,-99,0.0
evt_008,0,1.1
evt_009,null,5.5
evt_010,1004,8.8
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
