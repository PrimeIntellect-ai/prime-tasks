#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/config_changes.csv
1700002850,srv-01,10
1700003400,srv-02,20
1700007000,srv-01,40
1700010050,srv-03,20
1700014000,srv-01,70
1700018000,srv-02,10
1700025000,srv-04,60
EOF

    chmod -R 777 /home/user
