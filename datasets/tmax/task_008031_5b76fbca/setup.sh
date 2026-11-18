#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential unzip tar parallel
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import tarfile
import zipfile

def create_bdoc(filename, title, content):
    with open(filename, 'wb') as f:
        f.write(b'BDOC')
        f.write(struct.pack('<I', len(title)))
        f.write(title.encode('ascii'))
        f.write(struct.pack('<I', len(content)))
        f.write(content.encode('ascii'))

os.makedirs('/tmp/bdoc_setup/part1', exist_ok=True)
os.makedirs('/tmp/bdoc_setup/part2', exist_ok=True)

create_bdoc('/tmp/bdoc_setup/part1/doc1.bdoc', 'Architecture', 'The system uses a monolithic design with modular components.')
create_bdoc('/tmp/bdoc_setup/part1/doc2.bdoc', 'API Reference', 'Endpoints are RESTful and use JSON payloads.')
create_bdoc('/tmp/bdoc_setup/part2/doc3.bdoc', 'Deployment', 'Use the provided Docker Compose file to deploy the stack.')
create_bdoc('/tmp/bdoc_setup/part2/doc4.bdoc', 'Authentication', 'JWT tokens are required in the Authorization header.')

with tarfile.open('/tmp/bdoc_setup/part1.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/bdoc_setup/part1/doc1.bdoc', arcname='doc1.bdoc')
    tar.add('/tmp/bdoc_setup/part1/doc2.bdoc', arcname='doc2.bdoc')

with tarfile.open('/tmp/bdoc_setup/part2.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/bdoc_setup/part2/doc3.bdoc', arcname='doc3.bdoc')
    tar.add('/tmp/bdoc_setup/part2/doc4.bdoc', arcname='doc4.bdoc')

with zipfile.ZipFile('/home/user/docs_archive.zip', 'w') as zf:
    zf.write('/tmp/bdoc_setup/part1.tar.gz', 'part1.tar.gz')
    zf.write('/tmp/bdoc_setup/part2.tar.gz', 'part2.tar.gz')
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/setup.py /tmp/bdoc_setup

    chown -R user:user /home/user
    chmod -R 777 /home/user
