#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/inventory.csv
host_id,region,environment
web-01,us-east,prod
web-02,us-east,prod
db-01,us-east,prod
app-01,eu-west,dev
app-02,eu-west,prod
EOF

    cat << 'EOF' > /home/user/config_logs.txt
[2023-11-01] EVENT: config_update HOST: web-01 PARAM: max_connections VAL: 100
[2023-11-01] EVENT: config_update HOST: web-01 PARAM: timeout VAL: 30
[2023-11-01] EVENT: config_update HOST: web-02 PARAM: max_connections VAL: 150
[2023-11-01] EVENT: config_update HOST: app-01 PARAM: debug_mode VAL: true
[2023-11-02] EVENT: config_update HOST: web-01 PARAM: max_connections VAL: 200
[2023-11-02] EVENT: config_update HOST: db-01 PARAM: buffer_pool VAL: 4G
[2023-11-02] EVENT: config_update HOST: db-01 PARAM: cache_size VAL: 2G
[2023-11-02] EVENT: config_update HOST: app-02 PARAM: threads VAL: 16
[2023-11-03] EVENT: config_update HOST: web-02 PARAM: timeout VAL: 60
[2023-11-03] EVENT: config_update HOST: app-01 PARAM: debug_mode VAL: false
[2023-11-03] EVENT: config_update HOST: app-01 PARAM: threads VAL: 8
EOF

    chmod -R 777 /home/user
