#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile

os.makedirs('/home/user/incoming', exist_ok=True)
os.makedirs('/home/user/extracted', exist_ok=True)

# Create safe zip 1
safe1_path = '/tmp/safe1.zip'
with zipfile.ZipFile(safe1_path, 'w') as z:
    z.writestr('users.csv', 'id,username,role\n1,admin,superuser\n2,bob,editor\n')
    z.writestr('readme.txt', 'Backup instructions.')

# Create safe zip 2
safe2_path = '/tmp/safe2.zip'
with zipfile.ZipFile(safe2_path, 'w') as z:
    z.writestr('config.bin', b'\x00\x01\x02\x03\x04')

# Create malicious zip 1
mal1_path = '/tmp/mal1.zip'
with zipfile.ZipFile(mal1_path, 'w') as z:
    z.writestr('safe_file.txt', 'Nothing to see here.')
    z.writestr('../../../home/user/.bashrc', 'echo "pwned"')

# Create malicious zip 2
mal2_path = '/tmp/mal2.zip'
with zipfile.ZipFile(mal2_path, 'w') as z:
    z.writestr('/etc/shadow', 'root:*:18330:0:99999:7:::')
    z.writestr('normal_dir/path.txt', 'ok')

# Package into backup.tar
with tarfile.open('/home/user/incoming/backup.tar', 'w') as t:
    t.add(safe1_path, arcname='documents.zip')
    t.add(safe2_path, arcname='system_bins.zip')
    t.add(mal1_path, arcname='user_profiles.zip')
    t.add(mal2_path, arcname='core_sys.zip')

# Cleanup tmp files
os.remove(safe1_path)
os.remove(safe2_path)
os.remove(mal1_path)
os.remove(mal2_path)
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

chmod -R 777 /home/user
