#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/locks.csv
tx_id,resource_held,resource_requested
T01,RES_12,
T02,RES_05,RES_17
T03,RES_08,RES_05
T04,RES_17,RES_09
T05,RES_01,RES_22
T06,RES_09,RES_33
T07,,RES_12
T08,RES_33,RES_08
T09,RES_22,
EOF

    chmod -R 777 /home/user
