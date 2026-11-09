#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go curl procps
pip3 install pytest

# Create server directory and generate the raw log file
mkdir -p /home/user/server
cat << 'EOF' > /home/user/server/generate_log.py
with open('/home/user/server/raw.log', 'wb') as f:
    f.write(b'[2023-10-01T10:00:00.000Z] System startup.\n')
    f.write(b'[???] CPU temp is high: 95\xb0C.\n')
    f.write(b'[???] Warning: fan speed \x96 critical!\n')
    f.write(b'[2023-10-01T10:00:03.000Z] System stabilized.\n')
    f.write(b'[2023-10-01T10:00:04.000Z] User a\xcc\x88 logged in.\n')
EOF
python3 /home/user/server/generate_log.py

# Ensure the server starts when a shell is opened
echo "pgrep -f 'python3 -m http.server 8080' > /dev/null || (cd /home/user/server && python3 -m http.server 8080 >/dev/null 2>&1 &)" >> /etc/bash.bashrc

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
