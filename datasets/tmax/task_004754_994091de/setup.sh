#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/service

cat << 'EOF' > /home/user/service/start_service.sh
#!/bin/bash

PID_FILE="/home/user/service/run/service.pid"
DATA_DIR="/home/user/service/data"
STATUS_FILE="$DATA_DIR/status.txt"

if [ -f "$PID_FILE" ]; then
    echo "Error: PID file exists. Service may already be running."
    exit 1
fi

# This will fail because /home/user/service/run doesn't exist
echo $$ > "$PID_FILE" || exit 1

# This will fail because /home/user/service/data doesn't exist
echo "ACTIVE" > "$STATUS_FILE" || exit 1

# Simulate service work
while true; do
    sleep 10
done
EOF

chmod +x /home/user/service/start_service.sh

chmod -R 777 /home/user
