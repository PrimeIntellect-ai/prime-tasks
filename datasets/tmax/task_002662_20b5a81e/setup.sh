#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/extracted_configs

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
import json
import shutil

os.makedirs('/home/user/temp_setup/v1', exist_ok=True)
os.makedirs('/home/user/temp_setup/v2', exist_ok=True)
os.makedirs('/home/user/temp_setup/v3', exist_ok=True)

# Create JSON configs
v1 = {"app_name": "myapp", "port": 8080, "db_host": "localhost", "debug": False, "static_key": "unchanged"}
v2 = {"app_name": "myapp", "port": 8081, "db_host": "db.local", "debug": True, "static_key": "unchanged"}
v3 = {"app_name": "myapp_v2", "port": 8081, "db_host": "db.prod", "debug": True, "timeout": 30, "static_key": "unchanged"}

with open('/home/user/temp_setup/v1/config.json', 'w') as f: json.dump(v1, f)
with open('/home/user/temp_setup/v2/config.json', 'w') as f: json.dump(v2, f)
with open('/home/user/temp_setup/v3/config.json', 'w') as f: json.dump(v3, f)

# Create Zip files
with zipfile.ZipFile('/home/user/part1.zip', 'w') as z:
    z.write('/home/user/temp_setup/v1/config.json', 'v1/config.json')

with zipfile.ZipFile('/home/user/part2.zip', 'w') as z:
    z.write('/home/user/temp_setup/v2/config.json', 'v2/config.json')
    # Malicious zip slip entry
    z.writestr('../escaped_system_config.json', '{"pwned": true}')
    z.writestr('v2/../../etc/passwd_fake', 'root:x:0:0:')

with zipfile.ZipFile('/home/user/part3.zip', 'w') as z:
    z.write('/home/user/temp_setup/v3/config.json', 'v3/config.json')

# Tar them up
with tarfile.open('/home/user/config_backup.tar.gz', 'w:gz') as tar:
    tar.add('/home/user/part1.zip', arcname='part1.zip')
    tar.add('/home/user/part2.zip', arcname='part2.zip')
    tar.add('/home/user/part3.zip', arcname='part3.zip')

# Cleanup
shutil.rmtree('/home/user/temp_setup')
os.remove('/home/user/part1.zip')
os.remove('/home/user/part2.zip')
os.remove('/home/user/part3.zip')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
