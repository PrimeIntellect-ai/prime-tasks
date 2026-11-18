#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build
    mkdir -p /home/user/bin
    echo 'import time; time.sleep(10000)' > /home/user/build/server.py
    echo 'print("OK")' > /home/user/build/healthcheck.py
    cd /home/user/build && zip app.zip server.py healthcheck.py
    rm server.py healthcheck.py

    cat << 'EOF' > /home/user/ci_webhook.json
{
    "artifact": "/home/user/build/app.zip",
    "target_dir": "/home/user/app_root",
    "disk_image": "/home/user/storage.img",
    "mount_point": "/home/user/app_root/storage"
}
EOF

    touch /home/user/mock_fstab

    chown -R user:user /home/user
    chmod -R 777 /home/user
