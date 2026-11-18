#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip netcat-openbsd
pip3 install pytest

# Create corpora directories
mkdir -p /app/corpora/clean
mkdir -p /app/corpora/evil

# Create clean logs
cat << 'EOF' > /app/corpora/clean/clean1.log
[2023-10-01T12:00:00Z] INFO: latency=45.2ms query="SELECT * FROM users"
[2023-10-01T12:00:01Z] INFO: latency=12.0ms query="SELECT * FROM posts"
[2023-10-01T12:00:02Z] INFO: latency=0.5ms query="SELECT * FROM comments"
EOF

# Create evil logs
cat << 'EOF' > /app/corpora/evil/evil1.log
[2023-10-01T12:00:00Z] INFO: latency=-45.2ms query="SELECT * FROM users"
[2023-10-01T12:00:01Z] INFO: latency=NaNms query="SELECT * FROM posts"
[2023-10-01T12:00:02Z] INFO: latency=nullms query="SELECT * FROM comments"
[2023-10-01T12:00:03Z] INFO: latency=-0.1ms query="SELECT * FROM users"
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
