#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/config

    cat << 'EOF' > /home/user/logs/http.log
2023-10-25T10:00:01Z | 10.0.0.5 | GET | /index.html | {"User-Agent": "Mozilla", "Cookie": "Session-Id=normal_user_11"} | 200
2023-10-25T10:05:22Z | 192.168.1.100 | POST | /upload?dir=images | {"User-Agent": "curl/7.68.0", "Cookie": "Session-Id=hacker_sess_9988"} | 403
2023-10-25T10:12:45Z | 172.16.0.4 | POST | /upload?dir=../../../../etc/cron.d | {"User-Agent": "Python-urllib/3.8", "Cookie": "Session-Id=malicious_xyz_7734"} | 200
2023-10-25T10:15:00Z | 10.0.0.5 | GET | /dashboard | {"User-Agent": "Mozilla", "Cookie": "Session-Id=normal_user_11"} | 200
EOF

    cat << 'EOF' > /home/user/config/db.conf
# Database Configuration
DB_HOST=127.0.0.1
DB_PORT=5432
DB_USER=admin
DB_PASSWORD=old_compromised_pass_123
DB_NAME=production_db
EOF

    chmod 644 /home/user/logs/http.log
    chmod 644 /home/user/config/db.conf

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
