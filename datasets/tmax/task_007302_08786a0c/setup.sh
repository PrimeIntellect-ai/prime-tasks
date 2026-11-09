#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest filelock

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import zipfile
import io

os.makedirs('/home/user/old_backups', exist_ok=True)

# Contents to duplicate
content_A = b"ERROR: Disk full\n"
content_B = b"WARN: High memory usage\n"
content_C = b"INFO: System rebooted\n"

# Create backup1
zip1_buffer = io.BytesIO()
with zipfile.ZipFile(zip1_buffer, 'w') as zf:
    zf.writestr('logA.log', content_A)
    zf.writestr('logB.log', content_B)

with tarfile.open('/home/user/old_backups/backup1.tar', 'w') as tf:
    tarinfo = tarfile.TarInfo(name='logs1.zip')
    tarinfo.size = len(zip1_buffer.getvalue())
    zip1_buffer.seek(0)
    tf.addfile(tarinfo, zip1_buffer)

# Create backup2
zip2_buffer = io.BytesIO()
with zipfile.ZipFile(zip2_buffer, 'w') as zf:
    zf.writestr('logC.log', content_C)
    zf.writestr('logA_dup.log', content_A)

with tarfile.open('/home/user/old_backups/backup2.tar', 'w') as tf:
    tarinfo = tarfile.TarInfo(name='logs2.zip')
    tarinfo.size = len(zip2_buffer.getvalue())
    zip2_buffer.seek(0)
    tf.addfile(tarinfo, zip2_buffer)

# Create backup3
zip3_buffer = io.BytesIO()
with zipfile.ZipFile(zip3_buffer, 'w') as zf:
    zf.writestr('logB_dup.log', content_B)

with tarfile.open('/home/user/old_backups/backup3.tar', 'w') as tf:
    tarinfo = tarfile.TarInfo(name='logs3.zip')
    tarinfo.size = len(zip3_buffer.getvalue())
    zip3_buffer.seek(0)
    tf.addfile(tarinfo, zip3_buffer)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
