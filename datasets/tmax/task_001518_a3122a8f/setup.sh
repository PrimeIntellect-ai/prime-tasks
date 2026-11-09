#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd cron
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/logs
cat << 'EOF' > /home/user/query_health.sh
#!/bin/bash
if [ -z "$LOG_DIR" ]; then
    LOG_DIR="/tmp"
fi
nc 127.0.0.1 8080 > "$LOG_DIR/status.log"
EOF
chmod +x /home/user/query_health.sh

echo "* * * * * /home/user/query_health.sh" | crontab -

chmod -R 777 /home/user
