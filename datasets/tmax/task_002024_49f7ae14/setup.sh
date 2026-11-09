#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang coreutils
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' | base64 -d > /home/user/legacy_rules.bin
UAlkMgEAAAMAAABkAAAABnJ1bGVfYQYAAAABAgAEBQEAAABlAAAABnJ1bGVfYgUAAAABAwACAwAAAGYAAAAGcnVsZV9jBAAAAAEFAAAF
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
