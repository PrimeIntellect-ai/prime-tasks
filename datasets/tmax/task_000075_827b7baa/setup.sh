#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip build-essential
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user

cat << 'EOF' > /home/user/changes.txt
{"cfg_id": 10, "delta": 2.50, "status": "active"}
{"cfg_id": 10, "delta": 4.50, "status": "\u0061\u0063\u0074\u0069\u0076\u0065"}
{"cfg_id": 20, "delta": -1.00, "status": "\u0069\u006E\u0061\u0063\u0074\u0069\u0076\u0065"}
{"cfg_id": 20, "delta": 5.00, "status": "inactive"}
{"cfg_id": 30, "delta": 10.00, "status": "active"}
{"cfg_id": 30, "delta": 20.00, "status": "\u0061\u0063\u0074\u0069\u0076\u0065"}
{"cfg_id": 30, "delta": -6.00, "status": "active"}
{"cfg_id": 45, "delta": 0.00, "status": "\u0061\u0063\u0074\u0069\u0076\u0065"}
EOF

chmod -R 777 /home/user
