#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs/existing
    echo "Old Documentation\nLine 2" > /home/user/docs/existing/old_doc.md
    touch -d "2 days ago" /home/user/docs/existing/old_doc.md

    cat << 'EOF' > /tmp/setup_tar.py
import tarfile
import os

os.chdir('/tmp')

with open('valid1.md', 'w') as f: f.write("Content of valid1\n")
with open('valid2.md', 'w') as f: f.write("Content of valid2\n")
with open('bad.md', 'w') as f: f.write("Malicious content\n")

with tarfile.open('/home/user/updates.tar', 'w') as tar:
    tar.add('valid1.md', arcname='valid1.md')
    tar.add('valid2.md', arcname='subdir/valid2.md')

    info1 = tar.gettarinfo('bad.md')
    info1.name = '../escaped.md'
    with open('bad.md', 'rb') as f:
        tar.addfile(info1, f)

    info2 = tar.gettarinfo('bad.md')
    info2.name = '/home/user/absolute.md'
    with open('bad.md', 'rb') as f:
        tar.addfile(info2, f)
EOF
    python3 /tmp/setup_tar.py
    rm /tmp/setup_tar.py /tmp/valid1.md /tmp/valid2.md /tmp/bad.md

    chown -R user:user /home/user/docs /home/user/updates.tar
    chmod -R 777 /home/user
