#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incoming
mkdir -p /home/user/app_configs

cat << 'EOF' > /home/user/create_zip.py
import zipfile

with zipfile.ZipFile('/home/user/incoming/updates.zip', 'w') as z:
    # Valid files
    z.writestr('network.conf', 'port=8080\nhost=0.0.0.0\n')
    z.writestr('plugins/db.conf', 'engine=sqlite\nworkers=4\n')

    # Malicious files (Zip Slip)
    z.writestr('../../../home/user/.bash_profile', 'echo "hacked"\n')
    z.writestr('plugins/../../shadow_backup.conf', 'user=admin\n')
EOF

python3 /home/user/create_zip.py
rm /home/user/create_zip.py

chmod -R 777 /home/user
