#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/service_a.log
2023-10-25T10:00:00Z [INFO] Pipeline started
2023-10-25T10:00:15Z [INFO] Pipeline finished with errors
EOF

    cat << 'EOF' > /home/user/logs/service_b.log
1698228005 [DEBUG] Loading configuration from config.env
1698228008 [WARN] Retrying connection
EOF

    cat << 'EOF' > /home/user/logs/service_c.log
Oct 25 10:00:10 [ERROR] Data sync failed: SYNC_TIMEOUT is not set or empty
EOF

    cat << 'EOF' > /home/user/config.env
export DB_HOST="localhost"
export DB_PORT=5432
export SYNC_TIMOUT=30  # Typo here
EOF

    cat << 'EOF' > /home/user/run_sync.sh
#!/bin/bash
source /home/user/config.env

if [ -z "$SYNC_TIMEOUT" ]; then
    echo "ERROR: SYNC_TIMEOUT environment variable is missing!" >&2
    exit 1
fi

echo "SYNC SUCCESS"
exit 0
EOF
    chmod +x /home/user/run_sync.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
