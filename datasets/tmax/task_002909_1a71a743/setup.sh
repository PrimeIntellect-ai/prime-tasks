#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/config /home/user/backups /home/user/run /home/user/logs

    cat << 'EOF' > /home/user/config/app.conf
# Application Config
log_level=debug
upstream_socket=/home/user/run/agregator.sock
timeout=30s
EOF

    cat << 'EOF' > /home/user/supervisor.sh
#!/bin/bash
DAEMON="/home/user/bin/log_aggregator"

while true; do
    echo "Starting daemon..."
    # $DAEMON
    # Daemon crashed!
    echo "Daemon exited with code $?"
    # Missing sleep here
done
EOF
    chmod +x /home/user/supervisor.sh

    cat << 'EOF' > /home/user/logs/error.log
2023-10-25 14:01:12 ERROR [app] Connection refused to /home/user/run/agregator.sock
2023-10-25 14:01:25 INFO [app] Retrying connection...
2023-10-25 14:01:26 ERROR [app] Connection refused to /home/user/run/agregator.sock
2023-10-25 14:01:59 ERROR [app] Connection refused to /home/user/run/agregator.sock
2023-10-25 14:02:05 ERROR [app] Timeout waiting for socket
2023-10-25 14:02:10 ERROR [app] Connection refused to /home/user/run/agregator.sock
2023-10-25 14:02:45 ERROR [app] Connection refused to /home/user/run/agregator.sock
2023-10-25 14:04:00 ERROR [app] Connection refused to /home/user/run/agregator.sock
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
