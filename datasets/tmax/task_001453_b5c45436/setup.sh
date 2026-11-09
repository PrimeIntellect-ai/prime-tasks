#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip unzip zip
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > setup.py
import os
import zipfile
import tarfile

base_dir = '/home/user'
os.makedirs(base_dir, exist_ok=True)

changelog_content = """Commit: 123
Author: Alice
Message: Fixed typos in docs
---
Commit: 124
Author: Bob
Message: Updated security protocols
Files changed: auth.py, login.py
Reviewer: Eve
---
Commit: 125
Author: Charlie
Message: Initial release
"""
with open('changelog.log', 'w') as f:
    f.write(changelog_content)

zip_path = os.path.join(base_dir, 'bundle.zip')
with zipfile.ZipFile(zip_path, 'w') as zf:
    zf.write('changelog.log', 'changelog.log')
    zf.writestr('../../../../home/user/evil.sh', 'echo "hacked"')
    zf.writestr('docs/readme.md', '# Readme')

tar_path = os.path.join(base_dir, 'docs_receipt.tar.gz')
with tarfile.open(tar_path, 'w:gz') as tf:
    tf.add(zip_path, arcname='bundle.zip')

os.remove('changelog.log')
os.remove(zip_path)
EOF

python3 setup.py
rm setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
