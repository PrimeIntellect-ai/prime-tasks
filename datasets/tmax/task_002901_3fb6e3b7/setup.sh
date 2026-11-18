#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tar
    pip3 install pytest

    mkdir -p /home/user/artifacts

    # Create a python script to generate a tar file with explicit, potentially malicious paths
    cat << 'EOF' > /tmp/make_tar.py
import tarfile

with tarfile.open('/home/user/artifacts/update.tar', 'w') as tar:
    def add_empty(name):
        ti = tarfile.TarInfo(name)
        ti.size = 0
        tar.addfile(ti)

    add_empty('lib/math.o')
    add_empty('include/math.h')
    add_empty('../../../../home/user/.bashrc')
    add_empty('/etc/passwd')
    add_empty('docs/readme.txt')
    add_empty('src/../lib/evil.o')
EOF

    python3 /tmp/make_tar.py
    rm /tmp/make_tar.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
