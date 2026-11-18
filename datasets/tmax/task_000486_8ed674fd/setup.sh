#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl openssl
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/accounts_data
cat << 'EOF' > /home/user/accounts_data/users.json
{"users": ["admin", "guest"]}
EOF

cat << 'EOF' > /home/user/config.fstab
# Mock fstab
rootfs / ext4 defaults 1 1
accounts_mount /home/user/accounts_data ext4 defaults 0 0
tmpfs /tmp tmpfs defaults 0 0
EOF

chmod -R 777 /home/user
