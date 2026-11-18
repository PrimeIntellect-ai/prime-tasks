#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import io

os.makedirs('/home/user/storage_dumps', exist_ok=True)
os.makedirs('/home/user/extracted_logs', exist_ok=True)

def create_tar(tar_name, entries):
    with tarfile.open(tar_name, 'w') as tar:
        for path, content in entries:
            info = tarfile.TarInfo(name=path)
            info.size = len(content)
            tar.addfile(tarinfo=info, fileobj=io.BytesIO(content))

log1 = b"""---
Timestamp: 2023-11-01T08:00:00Z
Severity: INFO
Message: System boot successful.
---
Timestamp: 2023-11-01T09:12:34Z
Severity: ERROR
Message: Disk space critical on /home
User intervention required.
---
Timestamp: 2023-11-01T10:00:00Z
Severity: WARNING
Message: High memory usage.
---
"""

log2 = b"""---
Timestamp: 2023-10-15T14:22:10Z
Severity: ERROR
Message: Disk space critical on /var/log
Purging old logs failed.
---
Timestamp: 2023-10-15T15:00:00Z
Severity: ERROR
Message: Network timeout reached.
---
"""

tar1_entries = [
    ("../../../etc/shadow", b"root:$6$xyz:19000:0:99999:7:::"),
    ("logs/safe_log1.log", log1),
    ("/root/.ssh/authorized_keys", b"ssh-rsa AAAAB3N... hacker@evil")
]

tar2_entries = [
    ("logs/safe_log2.log", log2),
    ("../../var/backups/shadow.bak", b"root:$6$xyz..."),
    ("safe_directory/../../etc/passwd", b"root:x:0:0:root:/root:/bin/bash")
]

tar1_path = '/home/user/backup_A.tar'
tar2_path = '/home/user/backup_B.tar'

create_tar(tar1_path, tar1_entries)
create_tar(tar2_path, tar2_entries)

def split_file(filepath, chunk_size=512):
    with open(filepath, 'rb') as f:
        data = f.read()

    base_name = os.path.basename(filepath)
    part_num = 1
    for i in range(0, len(data), chunk_size):
        chunk = data[i:i+chunk_size]
        part_name = f"/home/user/storage_dumps/{base_name}.part{part_num}"
        with open(part_name, 'wb') as f:
            f.write(chunk)
        part_num += 1
    os.remove(filepath)

split_file(tar1_path, 2048)
split_file(tar2_path, 2048)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
