#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backups_metadata.jsonl
{"backup_id": "b1", "database_name": "auth_db", "region": "us-east-1", "status": "SUCCESS", "timestamp": "2023-10-01T02:00:00Z", "size_bytes": 10485760}
{"backup_id": "b2", "database_name": "auth_db", "region": "us-east-1", "status": "FAILED", "timestamp": "2023-10-02T02:00:00Z", "size_bytes": 10485000}
{"backup_id": "b3", "database_name": "auth_db", "region": "us-east-1", "status": "SUCCESS", "timestamp": "2023-10-03T02:00:00Z", "size_bytes": 11000000}
{"backup_id": "b4", "database_name": "payment_db", "region": "us-east-1", "status": "SUCCESS", "timestamp": "2023-10-01T03:00:00Z", "size_bytes": 52428800}
{"backup_id": "b5", "database_name": "payment_db", "region": "us-east-1", "status": "SUCCESS", "timestamp": "2023-10-02T03:00:00Z", "size_bytes": 53000000}
{"backup_id": "b6", "database_name": "inventory_db", "region": "eu-west-1", "status": "SUCCESS", "timestamp": "2023-10-01T04:00:00Z", "size_bytes": 8388608}
{"backup_id": "b7", "database_name": "inventory_db", "region": "eu-west-1", "status": "IN_PROGRESS", "timestamp": "2023-10-04T04:00:00Z", "size_bytes": 4000000}
{"backup_id": "b8", "database_name": "auth_db", "region": "eu-west-1", "status": "SUCCESS", "timestamp": "2023-10-01T02:00:00Z", "size_bytes": 10485760}
EOF

    chmod -R 777 /home/user
