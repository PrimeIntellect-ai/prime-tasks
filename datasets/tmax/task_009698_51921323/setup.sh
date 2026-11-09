#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_loc_events.csv
ts,ip,loc_key,conf
3610,10.0.0.5,BTN_OK,90
3610,10.0.0.5,BTN_OK,90
3650,10.0.2.12,BTN_OK,80
3700,10.0.1.5,BTN_CANCEL,95
7210,192.168.1.1,BTN_OK,100
7210,192.168.1.1,BTN_OK,100
7500,192.168.2.250,BTN_OK,90
EOF

    chmod -R 777 /home/user
