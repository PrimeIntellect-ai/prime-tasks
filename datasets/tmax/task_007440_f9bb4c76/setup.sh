#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/data/app1_configs.jsonl
{"timestamp": 1620000010, "app_id": "app1", "service": "web_front", "memory_limit_mb": 100}
{"timestamp": 1620000030, "app_id": "app1", "service": "web_back_\uXYZA", "memory_limit_mb": 200}
{"timestamp": 1620000050, "app_id": "app1", "service": "cache_\u2603", "memory_limit_mb": 150}
{"timestamp": 1620000070, "app_id": "app1", "service": "db_read_\uG000", "memory_limit_mb": 500}
EOF

    cat << 'EOF' > /home/user/data/app2_configs.jsonl
{"timestamp": 1620000020, "app_id": "app2", "service": "api_v1", "memory_limit_mb": 300}
{"timestamp": 1620000040, "app_id": "app2", "service": "api_v2_\u12G4", "memory_limit_mb": 400}
{"timestamp": 1620000060, "app_id": "app2", "service": "worker_\u0041", "memory_limit_mb": 250}
{"timestamp": 1620000080, "app_id": "app2", "service": "worker_2", "memory_limit_mb": 350}
EOF

    chown -R user:user /home/user/data
    chown -R user:user /home/user/output
    chmod -R 777 /home/user
