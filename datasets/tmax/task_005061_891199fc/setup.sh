#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/transactions.json
[
    {"_id": "TX-10", "waits_for": null, "operation": "backup_snapshot"},
    {"_id": "TX-11", "waits_for": "TX-10", "operation": "backup_metadata"},
    {"_id": "TX-42", "waits_for": "TX-88", "operation": "lock_table_users"},
    {"_id": "TX-88", "waits_for": "TX-12", "operation": "lock_table_billing"},
    {"_id": "TX-12", "waits_for": "TX-42", "operation": "lock_table_logs"},
    {"_id": "TX-50", "waits_for": "TX-42", "operation": "read_table_users"}
]
EOF

    chmod -R 777 /home/user
