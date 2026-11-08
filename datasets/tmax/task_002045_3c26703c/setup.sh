#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak gcc
pip3 install pytest

mkdir -p /app/updates

# Create audio fixture
espeak -w /app/auth_dictation.wav "echo bravo niner tango"

# Create legacy.log
cat << 'EOF' > /app/legacy.log
[RECORD START]
ID: 101
Key: max_connections
Value: 500
[RECORD END]
[RECORD START]
ID: 102
Key: timeout
Value: 30s
[RECORD END]
EOF

# Create valid tarball
mkdir -p /tmp/patch1/db/
echo "db_host=localhost" > /tmp/patch1/db/database.conf.tmp
tar -czf /app/updates/patch1.tar.gz -C /tmp patch1

# Create corrupted tarball
dd if=/dev/urandom of=/app/updates/corrupt.tar.gz bs=1024 count=10

# Create user and set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /app
chmod -R 777 /home/user
