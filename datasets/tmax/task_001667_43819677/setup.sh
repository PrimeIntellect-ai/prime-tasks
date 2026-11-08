#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk grep sed coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/raw_logs
mkdir -p /home/user/output

cat << 'EOF' > /home/user/raw_logs/server1.log
[2023-11-01T14:30:00Z] app-01 - ACTION: ADD - KEY: threads - VALUE: 10
[2023-11-01T14:30:00Z] app-01 - ACTION: ADD - KEY: threads - VALUE: 10
[2023-11-01T14:32:01Z] app-01 - ACTION: UPDATE - KEY: max_connections - VALUE: 500
MALFORMED LINE HERE
[2023-11-01T14:35:00Z] app-01 - ACTION: DELETE - KEY: debug_mode - VALUE: true
EOF

cat << 'EOF' > /home/user/raw_logs/server2.log
[2023-11-01T14:31:00Z] db-01 - ACTION: ADD - KEY: cache_size - VALUE: 1024
[2023-11-01T14:33:00Z] db-01 - ACTION: UPDATE - KEY: cache_size - VALUE: 2048
[2023-11-01T14:32:01Z] app-01 - ACTION: UPDATE - KEY: max_connections - VALUE: 500
[2023-11-01T14:36:00Z] db-01 - ACTION: UPDATE - KEY: timeout - VALUE: 30
[2023-11-01T14:36:00Z] db-01 - ACTION: UPDATE - KEY: timeout - VALUE: 30
[2023-11-01T14:33:00Z] db-01 - ACTION: UPDATE - KEY: cache_size - VALUE: 2048
EOF

chmod -R 777 /home/user
