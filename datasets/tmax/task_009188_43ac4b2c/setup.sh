#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create setup script to generate the environment
    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import json

os.makedirs('/home/user/updates', exist_ok=True)

# Create config.json
with open('/home/user/updates/config.json', 'w') as f:
    json.dump(["update_v1.zip", "update_v2_malicious.zip", "update_v3.zip", "ignored_update.zip"], f)

# Create safe update_v1.zip
with zipfile.ZipFile('/home/user/updates/update_v1.zip', 'w') as zf:
    zf.writestr('database.conf', b'host=localhost\nport=5432\n')
    zf.writestr('logging.conf', b'level=DEBUG\n')

# Create malicious update_v2_malicious.zip
with zipfile.ZipFile('/home/user/updates/update_v2_malicious.zip', 'w') as zf:
    zf.writestr('benign.conf', b'something=safe\n')
    # Zip slip entry
    info = zipfile.ZipInfo('../../../../home/user/.bashrc')
    zf.writestr(info, b'echo "hacked"')

# Create safe update_v3.zip
with zipfile.ZipFile('/home/user/updates/update_v3.zip', 'w') as zf:
    zf.writestr('cache.conf', b'redis_port=6379\n')

# Create ignored_update.zip (not in config.json, should not be extracted)
with zipfile.ZipFile('/home/user/updates/ignored_update.zip', 'w') as zf:
    zf.writestr('ignored.conf', b'ignored=true\n')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
