#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/log_v1.txt
INFO: Initialization sequence started.
DEBUG: Module A loaded.
[ARCHIVE_ME] Pre-check complete.
INFO: Network interface eth0 up.
DEBUG: Connection established to 10.0.0.5.
EOF

    cat << 'EOF' > /home/user/log_v2.txt
INFO: Initialization sequence started.
DEBUG: Module A loaded.
[ARCHIVE_ME] Pre-check complete.
INFO: Network interface eth0 up.
DEBUG: Connection established to 10.0.0.5.
INFO: Running scheduled tasks.
[ARCHIVE_ME] Warning: CPU temperature reached 90C!!!!!
DEBUG: Retrying connection to database....
[ARCHIVE_ME] Critical Error: Memory leak detected in thread 00000000.
INFO: System shutting down.
[ARCHIVE_ME] Shutdown        complete.
EOF

    chown user:user /home/user/log_v1.txt /home/user/log_v2.txt
    chmod -R 777 /home/user
