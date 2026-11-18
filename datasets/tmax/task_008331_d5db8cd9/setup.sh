#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import zipfile
import tarfile

def create_bx(path, magic=b'BX01', version=2, payload=b"testdata", length_override=None):
    with open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<H', version))
        length = length_override if length_override is not None else len(payload)
        f.write(struct.pack('<I', length))
        f.write(payload)

base_dir = '/home/user/incoming_artifacts'
os.makedirs(base_dir, exist_ok=True)
os.makedirs(f'{base_dir}/subdir', exist_ok=True)

# 1. Valid standalone file
create_bx(f'{base_dir}/valid1.bx', payload=b"hello world")

# 2. Invalid standalone file (wrong magic)
create_bx(f'{base_dir}/invalid_magic.bx', magic=b'XX01')

# 3. Invalid standalone file (version 1)
create_bx(f'{base_dir}/invalid_version.bx', version=1)

# 4. Valid file in subdir
create_bx(f'{base_dir}/subdir/valid2.bx', payload=b"rust programming is fun!")

# 5. Invalid file (truncated payload)
create_bx(f'{base_dir}/subdir/truncated.bx', payload=b"short", length_override=100)

# 6. Invalid file (trailing data)
create_bx(f'{base_dir}/subdir/trailing.bx', payload=b"data12345", length_override=4)

# 7. Create a ZIP with one valid and one invalid file
zip_path = f'{base_dir}/archive.zip'
with zipfile.ZipFile(zip_path, 'w') as zf:
    valid_path = f'/tmp/zip_valid.bx'
    invalid_path = f'/tmp/zip_invalid.bx'
    create_bx(valid_path, payload=b"inside zip file")
    create_bx(invalid_path, version=0)
    zf.write(valid_path, 'zip_valid.bx')
    zf.write(invalid_path, 'zip_invalid.bx')

# 8. Create a TAR.GZ with a valid file
tar_path = f'{base_dir}/archive.tar.gz'
with tarfile.open(tar_path, 'w:gz') as tf:
    valid_path = f'/tmp/tar_valid.bx'
    create_bx(valid_path, payload=b"inside tar gz")
    tf.add(valid_path, arcname='tar_valid.bx')
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
