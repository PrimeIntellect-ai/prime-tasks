#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk grep coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/pipeline.log
INFO Starting pipeline run
[DEPENDENCY] extract_users -> transform_users
[DEPENDENCY] extract_users -> join_tables
DEBUG memory usage 45MB
[DEPENDENCY] extract_transactions -> transform_transactions
[DEPENDENCY] extract_transactions -> join_tables
[DEPENDENCY] extract_transactions -> aggregate_daily
[DEPENDENCY] extract_transactions -> aggregate_monthly
[DEPENDENCY] extract_transactions -> anomaly_detection
INFO Mid-run checkpoint
[DEPENDENCY] join_tables -> load_data_warehouse
[DEPENDENCY] aggregate_daily -> load_data_warehouse
[DEPENDENCY] aggregate_monthly -> load_data_warehouse
[DEPENDENCY] anomaly_detection -> alert_system
ERROR failed to ping auth server
[DEPENDENCY] extract_inventory -> transform_inventory
[DEPENDENCY] extract_inventory -> join_tables
[DEPENDENCY] extract_inventory -> sync_external
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
