#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps coreutils
pip3 install pytest

mkdir -p /home/user/logs
mkdir -p /home/user/monitor

cat << 'EOF' > /home/user/logs/web.log
2023-10-01 10:00:01 [WEB] Service ping OK
2023-10-01 10:00:15 [WEB] Service ping OK
2023-10-01 10:00:45 [WEB] Timeout reached
EOF

cat << 'EOF' > /home/user/logs/db.log
2023-10-01 10:00:05 [DB] Query successful
2023-10-01 10:00:20 [DB] Query successful
2023-10-01 10:00:35 [DB] Query slow
EOF

cat << 'EOF' > /home/user/logs/api.log
2023-10-01 10:00:02 [API] Endpoint active
2023-10-01 10:00:10 [API] Endpoint active
2023-10-01 10:00:50 [API] Error 503
EOF

cat << 'EOF' > /home/user/monitor/uptime.sh
#!/bin/bash

check_service() {
    # Simulates a slow network call
    sleep 10 &
    wait $!
}

echo "Starting monitor..."
check_service &
pid=$!

sleep 1
# Timeout cancellation
kill -TERM $pid 2>/dev/null
echo "Cancelled check"
EOF

chmod +x /home/user/monitor/uptime.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
