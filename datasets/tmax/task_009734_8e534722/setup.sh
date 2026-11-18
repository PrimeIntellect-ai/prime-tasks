#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang sed gawk coreutils
pip3 install pytest

mkdir -p /home/user/active_logs/app1/subs
mkdir -p /home/user/active_logs/app2

cat << 'EOF' > /home/user/active_logs/app1/server.log
INFO Starting server
DEBUG User login IP: 192.168.1.50 success
ERROR Failed transaction SSN: 123-45-6789
INFO User logout
EOF

cat << 'EOF' > /home/user/active_logs/app1/subs/db.log
WARN Connection timeout IP: 10.0.0.1
INFO Reconnected
ERROR Duplicate entry SSN: 987-65-4321, IP: 172.16.254.1
EOF

cat << 'EOF' > /home/user/active_logs/app2/api.log
INFO Request received
INFO Processing SSN: 111-22-3333 for user
INFO Done
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
