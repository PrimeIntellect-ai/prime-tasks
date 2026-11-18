#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_backups/app1
    mkdir -p /home/user/log_backups/app2

    cat << 'EOF' > /home/user/log_backups/app1/server.txt
---START---
Time: 1700000005
Severity: WARN
Message: High memory usage
detected on node A.
---END---
Random garbage text that should be ignored.
---START---
Time: 1700000000
Severity: INFO
Message: Service started successfully.
---END---
EOF

    cat << 'EOF' > /home/user/log_backups/app2/db.txt
---START---
Time: 1700000010
Severity: CRIT
Message: Database connection lost!
Retrying...
Failed.
---END---
EOF

    chmod -R 777 /home/user
