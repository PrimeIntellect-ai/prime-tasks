#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user
cat << 'EOF' > /home/user/data.jsonl
{"time":"2023-01-01T12:00:10Z","alpha":"10.0\u00b0C","beta":"12.0\u00b0C"}
{"time":"2023-01-01T12:00:55Z","alpha":"10.1\u00b0C","beta":"12.1\u00b0C"}
{"time":"2023-01-01T12:02:15Z","alpha":"10.5\u00b0C","beta":"12.5\u00b0C"}
{"time":"2023-01-01T12:05:01Z","alpha":"11.2\u00b0C","beta":"13.0\u00b0C"}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
