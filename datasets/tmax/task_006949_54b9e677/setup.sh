#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc curl
pip3 install pytest

mkdir -p /home/user/backup /home/user/metrics

cat << 'EOF' > /home/user/legacy_app.log
2023-10-01 10:00:01 [INFO] Application started
2023-10-01 10:00:02 [WARN] Deprecated API used
2023-10-01 10:00:03 [ERROR] Database connection failed
2023-10-01 10:00:04 [INFO] Retrying connection
2023-10-01 10:00:05 [WARN] Connection slow
2023-10-01 10:00:06 [ERROR] Timeout reached
2023-10-01 10:00:07 [ERROR] Fatal exception in worker thread
2023-10-01 10:00:08 [INFO] Shutting down cleanly
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
