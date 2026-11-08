#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk grep coreutils
pip3 install pytest

mkdir -p /home/user/data
dd if=/dev/zero of=/home/user/data/file1.txt bs=1024 count=500
dd if=/dev/zero of=/home/user/data/file2.txt bs=1024 count=500
dd if=/dev/zero of=/home/user/data/file3.txt bs=1024 count=500
dd if=/dev/zero of=/home/user/data/file4.txt bs=1024 count=500

cat << 'EOF' > /home/user/data/manifest.txt
file1.txt STATUS=PROCESSED
file2.txt STATUS=PENDING
file3.txt STATUS=PROCESSED
file4.txt STATUS=ERROR
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
