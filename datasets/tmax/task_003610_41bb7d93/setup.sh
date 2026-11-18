#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cron
pip3 install pytest

mkdir -p /opt/remote
cat << 'EOF' > /opt/remote/web.log
[2023-10-01T12:00:01] IP: 10.0.0.1 | User-Agent: Mozilla/5.0 | ResponseTime: 12ms
[2023-10-01T12:00:02] IP: 10.0.0.2 | User-Agent: curl/7.68.0 | ResponseTime: 15ms
[2023-10-01T12:00:03] IP: 10.0.0.1 | User-Agent: Mozilla/5.0 | ResponseTime: 14ms
[2023-10-01T12:00:04] IP: 10.0.0.3 | User-Agent: Safari/537.36 | ResponseTime: 11ms
[2023-10-01T12:00:05] IP: 10.0.0.2 | User-Agent: curl/7.68.0 | ResponseTime: 13ms
[2023-10-01T12:00:06] IP: 192.168.1.100 | User-Agent: Python-urllib/3.8 | ResponseTime: 150ms
[2023-10-01T12:00:07] IP: 10.0.0.1 | User-Agent: Mozilla/5.0 | ResponseTime: 12ms
[2023-10-01T12:00:08] IP: 10.0.0.2 | User-Agent: curl/7.68.0 | ResponseTime: 14ms
[2023-10-01T12:00:09] IP: 192.168.1.101 | User-Agent: BadBot/1.0 | ResponseTime: 200ms
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
