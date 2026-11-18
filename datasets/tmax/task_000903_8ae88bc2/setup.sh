#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup_log.py
import fcntl

log_data = """[RECORD]
TIMESTAMP: 2023-10-25T10:00:00Z
LEVEL: INFO
MSG: Backup started
DETAILS: Initiated by cron
[/RECORD]
[RECORD]
TIMESTAMP: 2023-10-25T10:01:00Z
LEVEL: ERROR
MSG: Volume shadow copy failed
DETAILS: VSS writer error 0x8004231f
[/RECORD]
[RECORD]
TIMESTAMP: 2023-10-25T10:02:00Z
LEVEL: WARNING
MSG: Space running low
DETAILS: 5GB remaining on /backup
[/RECORD]
[RECORD]
TIMESTAMP: 2023-10-25T10:05:00Z
LEVEL: ERROR
MSG: Network timeout
DETAILS: Destination unreachable after 30s
[/RECORD]
"""

with open('/home/user/active_service.log', 'ab') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    f.write(log_data.encode('utf-16le'))
    fcntl.flock(f, fcntl.LOCK_UN)
EOF

    python3 /home/user/setup_log.py

    chmod -R 777 /home/user
