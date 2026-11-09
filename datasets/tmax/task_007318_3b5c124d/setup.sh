#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gzip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/config.ini
[Target]
Service=AuthWorker
EOF

    cat << 'EOF' > /home/user/logs/system_01.log
===RECORD===
Timestamp: 2023-10-12T10:00:00Z
Service: AuthWorker
Message: Login failed
===END===
===RECORD===
Timestamp: 2023-10-12T10:01:00Z
Service: WebApp
Message: Page loaded
===END===
EOF

    cat << 'EOF' > /home/user/logs/system_02.log
===RECORD===
Timestamp: 2023-10-12T10:05:00Z
Service: WebApp
Message: User clicked button
===END===
===RECORD===
Timestamp: 2023-10-12T10:06:00Z
Service: Payment
Message: Transaction success
===END===
EOF

    cat << 'EOF' > /home/user/logs/system_03.log
===RECORD===
Timestamp: 2023-10-12T10:10:00Z
Service: AuthWorker
Message: Token expired
===END===
===RECORD===
Timestamp: 2023-10-12T10:11:00Z
Service: AuthWorker
Message: Token renewed
===END===
EOF

    gzip /home/user/logs/system_01.log
    gzip /home/user/logs/system_02.log
    gzip /home/user/logs/system_03.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
