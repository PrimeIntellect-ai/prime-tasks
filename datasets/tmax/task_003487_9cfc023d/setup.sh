#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    # Create remote logs directory and files
    mkdir -p /tmp/remote_logs/

    cat << 'EOF' > /tmp/remote_logs/server1.txt
14-Feb-2024 08:00:00 -0500 | INFO | User logged in
14-Feb-2024 15:30:00 +0000 | ERROR | Database connection failed
14-Feb-2024 11:00:00 -0400 | WARNING | Disk space low
14-Feb-2024 12:00:00 -0800 | INFO | Job completed successfully
14-Feb-2024 22:00:00 +0200 | ERROR | Memory limit exceeded
EOF

    cat << 'EOF' > /tmp/remote_logs/server2.txt
14-Feb-2024 09:30:00 -0500 | INFO | User logged out
14-Feb-2024 17:45:00 +0100 | WARNING | High latency detected
14-Feb-2024 13:00:00 -0600 | INFO | Cache flushed
14-Feb-2024 14:15:00 -0500 | CRITICAL | System crash
14-Feb-2024 20:30:00 +0000 | ERROR | Timeout on API call
EOF

    # Create the user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chmod -R 777 /home/user
