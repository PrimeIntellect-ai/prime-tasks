#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/app_logs.txt
[2023-10-25 10:00:01] ERROR from 10.0.0.1: User 'alice' failed to login (Code: 401)
[2023-10-25 10:00:02] WARN connection timeout from unknown source
[2023-10-25 10:00:03] ERROR from 10.0.0.2: User 'bob' failed to login (Code: 403)
[2023-10-25 10:00:01] ERROR from 10.0.0.1: User 'alice' failed to login (Code: 401)
[2023-10-25 10:00:05] ERROR from 192.168.1.100: User 'charlie' failed to login (Code: 500)
Malformed line here, no brackets.
[2023-10-25 10:00:06] ERROR from 10.0.0.3: User 'david' failed to login (Code: 401)
[2023-10-25 10:00:05] ERROR from 192.168.1.100: User 'charlie' failed to login (Code: 500)
[2023-10-25 10:00:07] INFO User 'eve' logged in successfully
EOF

    chmod -R 777 /home/user
