#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest pandas networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/warehouses.csv
warehouse_id,capacity,current_stock
WH-01,1000,500
WH-02,800,200
WH-03,1200,1000
WH-04,500,100
WH-05,2000,500
EOF

    cat << 'EOF' > /home/user/routes.csv
source_id,target_id,transit_time_days
WH-01,WH-02,2
WH-02,WH-03,1
WH-01,WH-04,5
WH-04,WH-05,2
WH-02,WH-05,4
EOF

    chmod -R 777 /home/user
