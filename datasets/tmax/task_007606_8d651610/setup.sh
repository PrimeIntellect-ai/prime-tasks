#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import tarfile
import os

os.makedirs('/home/user/incoming_configs', exist_ok=True)
os.makedirs('/home/user/safe_configs', exist_ok=True)
os.makedirs('/home/user/quarantine_configs', exist_ok=True)

dummy_file = '/tmp/dummy_config_file'
with open(dummy_file, 'w') as f:
    f.write('{"setting": "value"}')

with tarfile.open('/home/user/incoming_configs/app1_update.tar', 'w') as t:
    t.add(dummy_file, arcname='app1/config.json')

with tarfile.open('/home/user/incoming_configs/app2_update.tar', 'w') as t:
    t.add(dummy_file, arcname='config.json')

with tarfile.open('/home/user/incoming_configs/evil_relative.tar', 'w') as t:
    t.add(dummy_file, arcname='../system/config.json')

with tarfile.open('/home/user/incoming_configs/evil_absolute.tar', 'w') as t:
    t.add(dummy_file, arcname='/etc/passwd_override')

with open('/home/user/incoming_configs/broken1.tar', 'wb') as f:
    f.write(b'This is just some random text, not a valid tar header or archive.')

with open('/home/user/incoming_configs/broken2.tar', 'wb') as f:
    f.write(b'\x00' * 1024)

os.remove(dummy_file)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
