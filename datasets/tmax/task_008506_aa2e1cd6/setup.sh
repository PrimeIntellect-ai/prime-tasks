#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import zipfile
import os

os.makedirs("/home/user", exist_ok=True)

config_ini = """[Settings]
admin_email=admin@example.com
backup_dir=/data/backup
max_retries=3
"""

wal_01 = """TXN01 SET max_retries 5
TXN02 APPEND backup_dir /daily
TXN03 SET alert_port 8080
"""

wal_02 = """TXN04 DELETE admin_email
TXN05 SET new_feature enabled
TXN06 APPEND backup_dir /v2
"""

zip_path = "/home/user/data_backup.zip"
with zipfile.ZipFile(zip_path, 'w') as zf:
    # Safe files
    zf.writestr("config.ini", config_ini)
    zf.writestr("01.wal", wal_01)
    zf.writestr("02.wal", wal_02)
    # Malicious files
    zf.writestr("../../../home/user/ssh_keys.txt", "fake ssh keys")
    zf.writestr("/var/run/daemon.pid", "1234")
    zf.writestr("safe_dir/../../etc/passwd", "fake passwd")
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
