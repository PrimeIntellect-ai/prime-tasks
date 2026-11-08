#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq cron coreutils
    pip3 install pytest python-Levenshtein

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cat << 'EOF' > /home/user/raw_events.log
2023-10-01T10:00:00 [ERROR] {"message": "DB connection timeout", "code": 500}
2023-10-01T10:01:00 [ERROR] {"message": "CRITICAL: DB connection timeout", "code": 500}
2023-10-01T10:02:00 [ERROR] {"message": "CRITICAL: DB connection timeout", "code": 500}
2023-10-01T10:03:00 [WARN] {"message": "High CPU usage detected", "code": 300}
2023-10-01T10:04:00 [ERROR] {"message": "CRITICAL: DB connection timout", "code": 500}
2023-10-01T10:05:00 [INFO] {"message": "System restart initiated", "code": 200}
2023-10-01T10:06:00 [ERROR] {"message": "CRITICAL: DB connection timeout", "code": 500}
EOF

    chmod -R 777 /home/user
