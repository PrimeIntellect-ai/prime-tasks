#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps gcc libc6-dev
pip3 install pytest

mkdir -p /home/user/artifacts/module_a
mkdir -p /home/user/artifacts/module_b

# Create regular files
echo "binary data 1" > /home/user/artifacts/bin1.dat
echo "binary data 2" > /home/user/artifacts/module_a/bin2.dat
echo "binary data 3" > /home/user/artifacts/module_b/bin3.dat

# Create valid symlinks
ln -s /home/user/artifacts/bin1.dat /home/user/artifacts/module_a/link_to_bin1.dat

# Create cyclic symlinks
ln -s /home/user/artifacts/loop2.sym /home/user/artifacts/loop1.sym
ln -s /home/user/artifacts/loop1.sym /home/user/artifacts/loop2.sym

# Create a locked file
echo "locked data" > /home/user/artifacts/locked.dat

# Create python locker script
cat << 'EOF' > /home/user/locker.py
import fcntl
import time
import sys

with open('/home/user/artifacts/locked.dat', 'r+') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    # keep it locked for an hour
    time.sleep(3600)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
