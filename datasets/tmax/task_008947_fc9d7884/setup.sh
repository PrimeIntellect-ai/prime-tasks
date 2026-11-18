#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import gzip
import shutil

os.makedirs('/home/user/staging', exist_ok=True)
os.chdir('/home/user/staging')

with open('dev_settings.csv', 'w') as f:
    f.write("key,value\ntheme,dark\nport,8080\n")

with open('dev_data.csv', 'w') as f:
    f.write("id,user\n1,admin\n2,guest\n")

with open('dev_background.png', 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR...')

with open('dev_icon.png', 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR...')

logs = b"INFO: Server started\nWARNING: High memory usage\nCRITICAL: Database connection lost\nINFO: Retrying connection\nCRITICAL: Disk full\nINFO: Shutting down\n"
with gzip.open('dev_server_logs.gz', 'wb') as f:
    f.write(logs)

with tarfile.open('/home/user/legacy_project.tar.gz', 'w:gz') as tar:
    for file_name in os.listdir('.'):
        tar.add(file_name)

os.chdir('/home/user')
shutil.rmtree('staging')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
