#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Vendor PyFileSystem2
    mkdir -p /app
    git clone https://github.com/PyFilesystem/pyfilesystem2.git /app/fs
    cd /app/fs
    git checkout v2.4.16

    # Perturb /app/fs/fs/osfs.py
    # This will cause infinite loop during traversal by ignoring symlink checks
    sed -i 's/entry.is_symlink()/False/g' fs/osfs.py
    sed -i 's/is_link()/False/g' fs/osfs.py

    # Create docs structure
    mkdir -p /home/user/docs/nested/folder
    touch /home/user/docs/file1.md /home/user/docs/nested/file2.md
    ln -s /home/user/docs /home/user/docs/nested/folder/loop_link

    # Generate metadata.bin
    cat << 'EOF' > /tmp/gen_metadata.py
import os
import random

file_size = 50000000
offsets = [1024, 50000, 1048576, 25000000, 49999992]

with open('/home/user/metadata.bin', 'wb') as f:
    # Write random data in chunks to save memory
    chunk_size = 1024 * 1024
    for _ in range(file_size // chunk_size + 1):
        f.write(os.urandom(chunk_size))

    f.truncate(file_size)

    for offset in offsets:
        f.seek(offset)
        f.write(b'DOC_MARK')
EOF
    python3 /tmp/gen_metadata.py
    rm /tmp/gen_metadata.py

    # Set permissions
    chown -R user:user /app/fs
    chmod -R 777 /app/fs
    chmod -R 777 /home/user
