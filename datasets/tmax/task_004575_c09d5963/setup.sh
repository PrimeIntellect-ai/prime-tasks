#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/service.log
[2023-10-25 10:00:00] INFO Service started
[2023-10-25 10:05:00] ERROR Connection timeout
Traceback (most recent call last):
  File "main.py", line 10, in <module>
TimeoutError: db unreachable
[2023-10-25 10:06:00] INFO Retrying connection
EOF

    chmod -R 777 /home/user
