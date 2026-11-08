#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app_logs

    cat << 'EOF' > /home/user/app_logs/web_access.log
[INFO] 10.0.0.1 - GET /login HTTP/1.1
[DEBUG] User authenticated successfully. Token: xJ92mA01
[INFO] 10.0.0.1 - GET /dashboard HTTP/1.1
[DEBUG] Checking session. Token: xJ92mA01
EOF

    cat << 'EOF' > /home/user/app_logs/api_error.log
[ERROR] Failed to fetch data. Token: Invalid883
[WARN] Rate limit exceeded for Token: RateLim55
[ERROR] Missing parameters.
EOF

    cat << 'EOF' > /home/user/app_logs/system.log
[INFO] System startup at 00:00:00.
[INFO] Loading modules...
[INFO] Ready.
EOF

    chmod -R 777 /home/user
    chmod 777 /home/user/app_logs
    chmod 644 /home/user/app_logs/*.log
