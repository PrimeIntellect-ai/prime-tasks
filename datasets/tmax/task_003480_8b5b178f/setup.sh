#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_task.py
import json

data = [
    # DB: users_db (Normal sizes ~ 1000)
    {"database": "users_db", "status": "success", "metrics": {"bytes": 1000}, "ts": "2023-10-01T10:00:00Z"},
    {"db": "users_db", "state": "ok", "size": 1100, "time": "2023-10-02T10:00:00Z"},
    {"database": "users_db", "status": "failed", "metrics": {"bytes": 0}, "ts": "2023-10-03T10:00:00Z"},
    {"database": "users_db", "status": "success", "metrics": {"bytes": 1050}, "ts": "2023-10-04T10:00:00Z"},
    # Anomaly 1: avg of prev 3 successful = (1000+1100+1050)/3 = 1050. 1.2 * 1050 = 1260.
    {"db": "users_db", "state": "success", "size": 1500, "time": "2023-10-05T10:00:00Z"}, 

    # DB: orders_db (Normal sizes ~ 5000)
    {"database": "orders_db", "status": "success", "metrics": {"bytes": 5000}, "ts": "2023-10-01T11:00:00Z"},
    {"db": "orders_db", "state": "success", "size": 4900, "time": "2023-10-02T11:00:00Z"},
    {"database": "orders_db", "status": "success", "metrics": {"bytes": 5100}, "ts": "2023-10-03T11:00:00Z"},
    # Anomaly 2: avg of prev 3 successful = (5000+4900+5100)/3 = 5000. 1.2 * 5000 = 6000.
    {"db": "orders_db", "state": "success", "size": 6500, "time": "2023-10-06T11:00:00Z"}, 
    {"database": "orders_db", "status": "success", "metrics": {"bytes": 5200}, "ts": "2023-10-07T11:00:00Z"},

    # DB: inventory_db (Normal sizes ~ 200)
    {"database": "inventory_db", "status": "success", "metrics": {"bytes": 200}, "ts": "2023-10-01T12:00:00Z"},
    # Anomaly 3 (only 1 prev): avg = 200. 1.2 * 200 = 240.
    {"db": "inventory_db", "state": "success", "size": 300, "time": "2023-10-02T12:00:00Z"},

    # Anomaly 4 (users_db again): prev 3 are 1100, 1050, 1500. Avg = 1216.66. 1.2 * 1216.66 = 1460.
    {"database": "users_db", "status": "success", "metrics": {"bytes": 2000}, "ts": "2023-10-08T10:00:00Z"}
]

with open('/home/user/raw_backups.jsonl', 'w') as f:
    for item in data:
        f.write(json.dumps(item) + '\n')
EOF
    python3 /tmp/setup_task.py
    rm /tmp/setup_task.py

    chmod -R 777 /home/user
