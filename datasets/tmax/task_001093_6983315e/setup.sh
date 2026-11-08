#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip espeak tar curl socat netcat-openbsd
pip3 install pytest

mkdir -p /app
espeak -w /app/voicemail.wav "Change max_worker_threads to 1024. Set cache_retention_days to 30. Change log_level to warn."

useradd -m -s /bin/bash user || true

cd /home/user
cat << 'EOF' > system.conf
max_worker_threads=256
cache_retention_days=7
log_level=info
database_url=postgres://localhost:5432
EOF

tar -czf config_archive.tar.gz system.conf
rm system.conf

chmod -R 777 /home/user
chmod -R 777 /app
