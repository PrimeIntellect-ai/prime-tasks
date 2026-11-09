#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip rustc cargo openssl
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/ids_logs.txt
[INFO] 2023-10-27 10:00:01 - System boot sequence initiated.
[WARN] 2023-10-27 10:05:12 - Unauthorized access attempt blocked from 192.168.1.50
[DEBUG] 2023-10-27 10:15:33 - PSK rotation complete. New key: 0x52303074
[INFO] 2023-10-27 10:20:00 - Routine scan completed with 0 anomalies.
EOF

echo "F1MIGBAnYhlEWEAxbUU2QXM5HxcDRS02C3U=" > /home/user/encrypted_payload.b64

chmod -R 777 /home/user
