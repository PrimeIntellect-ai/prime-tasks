#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/service_web.log
[INFO] Starting web server on port 8080...
[INFO] Attempting to connect to database...
[ERROR] Connection to db_backend failed: Connection refused.
[WARN] Retrying in 5 seconds...
EOF

    cat << 'EOF' > /home/user/logs/service_api.log
[INFO] API gateway initialized.
[INFO] All health checks passed.
[WARN] High memory usage detected.
EOF

    cat << 'EOF' > /home/user/logs/service_worker.log
[INFO] Worker process 12 started.
[INFO] Fetching jobs from queue...
[ERROR] Connection to redis_cache failed: No route to host.
[ERROR] Connection to redis_cache failed: Connection refused.
EOF

    cat << 'EOF' > /home/user/logs/service_auth.log
[INFO] Auth service booting.
[ERROR] Connection to ldap_server failed: Timeout.
EOF

    chmod -R 777 /home/user
