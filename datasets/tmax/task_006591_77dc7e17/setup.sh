#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest packaging

mkdir -p /home/user/inputs
cat << 'EOF' > /home/user/inputs/service_a.json
[
  {"plugin": "auth", "version": "1.0.5", "enabled": false},
  {"plugin": "db", "version": "2.1.0", "enabled": true}
]
EOF

cat << 'EOF' > /home/user/inputs/service_b.json
[
  {"plugin": "auth", "version": "1.2.0-alpha.1", "enabled": true},
  {"plugin": "cache", "version": "1.0.0", "enabled": true},
  {"plugin": "db", "version": "2.0.5", "enabled": true}
]
EOF

cat << 'EOF' > /home/user/inputs/service_c.json
[
  {"plugin": "auth", "version": "1.2.0", "enabled": false},
  {"plugin": "ui", "version": "3.0.0", "enabled": false}
]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
