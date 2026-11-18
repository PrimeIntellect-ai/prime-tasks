#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/incoming
    mkdir -p /home/user/docs
    mkdir -p /home/user/docs_backup

    # Create tarball with specific arcnames
    cat << 'EOF' > /tmp/create_tar.py
import tarfile
import io

with tarfile.open('/home/user/incoming/update.tar.gz', 'w:gz') as tar:
    def add_file(name, content):
        ti = tarfile.TarInfo(name)
        ti.size = len(content)
        tar.addfile(ti, io.BytesIO(content))

    add_file('new_feature.md', b"valid 1\n")
    add_file('subdir/nested.md', b"valid 2\n")
    add_file('../docs_backup/overwrite.md', b"malicious 1\n")
    add_file('/etc/passwd_fake', b"malicious 2\n")
EOF
    python3 /tmp/create_tar.py
    rm /tmp/create_tar.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
