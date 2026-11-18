#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backup_jobs.jsonl
{"job_id": "DB_Auth", "depends_on": []}
{"job_id": "DB_Users", "depends_on": ["DB_Auth"]}
{"job_id": "DB_Profiles", "depends_on": ["DB_Users"]}
{"job_id": "DB_Settings", "depends_on": ["DB_Users"]}
{"job_id": "DB_Logs", "depends_on": []}
{"job_id": "DB_Analytics", "depends_on": ["DB_Logs", "DB_Profiles"]}
{"job_id": "DB_Orders", "depends_on": ["DB_Payments"]}
{"job_id": "DB_Payments", "depends_on": ["DB_Invoices"]}
{"job_id": "DB_Invoices", "depends_on": ["DB_Orders"]}
{"job_id": "DB_Inventory", "depends_on": ["DB_Warehouse"]}
{"job_id": "DB_Warehouse", "depends_on": ["DB_Inventory"]}
{"job_id": "DB_Shipping", "depends_on": ["DB_Orders"]}
{"job_id": "DB_Tracking", "depends_on": ["DB_Shipping"]}
EOF

    chmod -R 777 /home/user
