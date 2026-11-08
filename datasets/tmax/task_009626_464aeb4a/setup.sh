#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/schema_fks.txt
orders users
orders products
products categories
users roles
roles permissions
audit_logs users
audit_logs actions
reviews users
reviews products
inventory products
inventory warehouses
user_sessions users
user_preferences users
EOF

    cat << 'EOF' > /home/user/critical_tables.txt
orders
inventory
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
