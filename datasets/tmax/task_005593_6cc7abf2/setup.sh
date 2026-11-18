#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libjson-c-dev
    pip3 install pytest

    mkdir -p /home/user/configs

    cat << 'EOF' > /home/user/configs/app1.json
{"app_name": "web_server", "config_version": 3, "workers": 4}
EOF

    cat << 'EOF' > /home/user/configs/app2.json
{"app_name": "db_backend", "config_version": 2, "cache": true}
EOF

    cat << 'EOF' > /home/user/configs/app3.json
{"app_name": "cache_layer", "config_version": 5, "size": 1024}
EOF

    python3 -c '
import struct
with open("/home/user/state.bin", "wb") as f:
    f.write(struct.pack("<32si", b"web_server", 3))
    f.write(struct.pack("<32si", b"db_backend", 1))
    f.write(struct.pack("<32si", b"queue_mgr", 4))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
