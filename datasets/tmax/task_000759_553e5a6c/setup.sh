#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cargo rustc
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean

    # Create dummy video
    ffmpeg -f lavfi -i testsrc=duration=5:size=1280x720:rate=30 -pix_fmt yuv420p /app/project_demo.mp4

    # Create corpus using Python
    cat << 'EOF' > /tmp/make_tars.py
import tarfile
import os

# Clean
with open('README.md', 'w') as f:
    f.write('hello')
with tarfile.open('/app/corpus/clean/clean1.tar', 'w') as tar:
    tar.add('README.md')

with open('dummy', 'wb') as f:
    f.write(b'hello')

# Evil 1: traversal
with tarfile.open('/app/corpus/evil/evil1.tar', 'w') as tar:
    ti = tarfile.TarInfo('../../../etc/shadow')
    ti.size = 5
    with open('dummy', 'rb') as f:
        tar.addfile(ti, f)

# Evil 2: absolute
with tarfile.open('/app/corpus/evil/evil2.tar', 'w') as tar:
    ti = tarfile.TarInfo('/var/run/secrets.txt')
    ti.size = 5
    with open('dummy', 'rb') as f:
        tar.addfile(ti, f)

# Evil 3: symlink
with tarfile.open('/app/corpus/evil/evil3.tar', 'w') as tar:
    ti = tarfile.TarInfo('link')
    ti.type = tarfile.SYMTYPE
    ti.linkname = '/etc'
    tar.addfile(ti)

os.remove('README.md')
os.remove('dummy')
EOF
    python3 /tmp/make_tars.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
