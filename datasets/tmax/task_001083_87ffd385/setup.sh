#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

# Create directories
mkdir -p /home/user/artifacts/dir_a /home/user/artifacts/dir_b

# Create standard file
dd if=/dev/urandom of=/home/user/artifacts/file1.bin bs=1024 count=120

# Create symlink loops
ln -s /home/user/artifacts/dir_a /home/user/artifacts/dir_a/loop

# Create validator fixture
mkdir -p /app
echo '#!/bin/bash' > /app/validator
echo 'echo "Validator placeholder"' >> /app/validator
chmod +x /app/validator

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
