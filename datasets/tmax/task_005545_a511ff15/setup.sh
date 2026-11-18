#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/snapshots

cat << 'EOF' > /tmp/setup.py
import os
import tarfile
import hashlib
import struct
import io

os.makedirs('/home/user/snapshots', exist_ok=True)

def create_snap(filename, version, commit, author, changes, corrupt=False):
    # Create changelog.txt
    changelog = f"Commit: {commit}\nAuthor: {author}\nChanges:\n"
    for c in changes:
        changelog += f" - {c}\n"

    # Create tar.gz in memory
    tar_stream = io.BytesIO()
    with tarfile.open(fileobj=tar_stream, mode='w:gz') as tar:
        cl_bytes = changelog.encode('utf-8')
        tinfo = tarfile.TarInfo(name='changelog.txt')
        tinfo.size = len(cl_bytes)
        tar.addfile(tinfo, io.BytesIO(cl_bytes))

    payload = tar_stream.getvalue()

    # Header components
    magic = b'SNAP'
    ver_bytes = struct.pack('<H', version)

    if corrupt:
        # Invalid hash
        checksum = b'\x00' * 16
    else:
        checksum = hashlib.md5(payload).digest()

    final_data = magic + ver_bytes + checksum + payload

    with open(f'/home/user/snapshots/{filename}', 'wb') as f:
        f.write(final_data)

# File 1: Valid
create_snap('01_init.snap', 1, '7a8f9e0', 'sysadmin', ['Initial deployment', 'Setup firewall rules'])

# File 2: Corrupt (Hash mismatch)
create_snap('02_bad.snap', 1, 'deadbeef', 'hacker', ['Injected backdoor'], corrupt=True)

# File 3: Valid
create_snap('03_update.snap', 2, 'b4c5d6e', 'devops_bob', ['Increased max connections', 'Updated SSL certificates', 'Removed old user accounts'])
EOF

python3 /tmp/setup.py
rm /tmp/setup.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
