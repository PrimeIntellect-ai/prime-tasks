#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_keys.json
[
  {"user_id": 1, "legacy_key": "alpha123"},
  {"user_id": 2, "legacy_key": "beta456"},
  {"user_id": 3, "legacy_key": "gamma789"}
]
EOF

    echo "super_secret_integration_key" > /home/user/hmac_secret.txt

    chmod -R 777 /home/user
