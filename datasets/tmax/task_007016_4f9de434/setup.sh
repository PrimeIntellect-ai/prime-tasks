#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifacts

    python3 -c "
import tarfile
import os

os.makedirs('/home/user/artifacts', exist_ok=True)

with open('/tmp/safe1.bin', 'wb') as f: f.write(b'safe data')
with open('/tmp/safe2.bin', 'wb') as f: f.write(b'safe data')
with open('/tmp/bad1.bin', 'wb') as f: f.write(b'malicious payload')
with open('/tmp/bad2.bin', 'wb') as f: f.write(b'malicious payload')

with tarfile.open('/home/user/artifacts/release_v2.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/safe1.bin', arcname='bin/safe1.bin')
    tar.add('/tmp/safe2.bin', arcname='config/safe2.bin')
    tar.add('/tmp/safe1.bin', arcname='scripts/install.sh')
    tar.add('/tmp/bad1.bin', arcname='../../etc/shadow')
    tar.add('/tmp/bad2.bin', arcname='/root/.ssh/authorized_keys')
    tar.add('/tmp/bad1.bin', arcname='bin/../../var/run/daemon.pid')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
