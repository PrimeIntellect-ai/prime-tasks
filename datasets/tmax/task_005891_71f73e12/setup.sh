#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev libc-bin
pip3 install pytest

mkdir -p /home/user/incoming
mkdir -p /home/user/backups

cat << 'EOF' > /tmp/raw_log1.txt
{"id":"BIN-001","note":"Initial release résumé"},
{"id":"BIN-002","note":"Patch update"}
EOF

cat << 'EOF' > /tmp/raw_log2.txt
{"id":"BIN-003","note":"Secürity fix"},
{"id":"BIN-004","note":"Deprecated"}
EOF

# Convert to UTF-16LE
iconv -f UTF-8 -t UTF-16LE /tmp/raw_log1.txt > /home/user/incoming/artifacts.log.1
iconv -f UTF-8 -t UTF-16LE /tmp/raw_log2.txt > /home/user/incoming/artifacts.log
rm /tmp/raw_log*.txt

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
