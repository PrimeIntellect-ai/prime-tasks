#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    mkdir -p /home/user/app_data

    cat << 'EOF' > /home/user/bin/service_worker
#!/bin/bash
TARGET_DIR="${APP_DIR:-/home/user}"
echo "worker started" > "$TARGET_DIR/data.log"
while true; do
    echo "data payload $(date +%s)" >> "$TARGET_DIR/data.log"
    sleep 1
done
EOF
    chmod +x /home/user/bin/service_worker

    cat << 'EOF' > /home/user/trigger_worker.sh
#!/bin/bash
# Trigger script for scheduler
/home/user/bin/service_worker &
EOF
    chmod +x /home/user/trigger_worker.sh

    chmod -R 777 /home/user
