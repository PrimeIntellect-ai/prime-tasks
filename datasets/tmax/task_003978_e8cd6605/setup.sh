#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import json
import random

random.seed(42)

servers = [f"server-{i:03d}" for i in range(1, 21)]
apps = [
    {"app_name": "nginx", "settings": {"worker_connections": 1024}, "description": "Web server - Веб-сервер"},
    {"app_name": "redis", "settings": {"maxmemory": "2gb"}, "description": "Cache - 缓存"},
    {"app_name": "postgres", "settings": {"shared_buffers": "4gb"}, "description": "Database - قاعدة البيانات"},
    {"settings": {"unknown": True}, "description": "Invalid config missing app_name"} # Invalid
]

with open("/home/user/raw_configs.jsonl", "w", encoding="utf-8") as f:
    for _ in range(500):
        server = random.choice(servers)
        app = random.choice(apps)
        base_ts = random.randint(1600000000, 1600005000)

        # Write original
        record = {
            "server_id": server,
            "timestamp": base_ts,
            "retry_id": 0,
            "config_data": app
        }
        f.write(json.dumps(record, ensure_ascii=False) + "\n")

        # Write 1-3 duplicates
        if "app_name" in app:
            for retry in range(1, random.randint(2, 4)):
                dup_record = {
                    "server_id": server,
                    "timestamp": base_ts + random.randint(5, 60), # Later timestamp
                    "retry_id": retry,
                    "config_data": app
                }
                f.write(json.dumps(dup_record, ensure_ascii=False) + "\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
