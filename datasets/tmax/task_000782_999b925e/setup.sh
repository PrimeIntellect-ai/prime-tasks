#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils gawk grep
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/backup_dependencies.txt
prod-users prod-orders
prod-users prod-inventory
prod-users prod-logs
prod-orders prod-shipping
prod-shipping prod-analytics
prod-inventory prod-shipping
dev-users dev-orders
prod-logs prod-metrics
staging-users staging-logs
prod-metrics staging-metrics
prod-analytics dev-analytics
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
