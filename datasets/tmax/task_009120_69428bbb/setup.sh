#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/backups.tsv
db_users	db_core
db_orders	db_users
db_payments	db_orders
db_logs	db_core
db_analytics	db_logs
db_reports	db_analytics
db_notifications	db_users
db_inventory	db_core
db_shipping	db_orders
EOF

    chmod -R 777 /home/user
