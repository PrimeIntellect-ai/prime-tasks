#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_data.log
LOG_TIME:2023-10-15T10:01:23Z | SID:S01 | VAL:20.0
LOG_TIME:2023-10-15T10:14:59Z | SID:S01 | VAL:22.0
LOG_TIME:2023-10-15T10:14:59Z | SID:S02 | VAL:15.0
LOG_TIME:2023-10-15T10:16:00Z | SID:S01 | VAL:25.0
LOG_TIME:2023-10-15T10:20:00Z | SID:S01 | VAL:150.0
LOG_TIME:2023-10-15T10:29:59Z | SID:S01 | VAL:27.0
LOG_TIME:2023-10-15T10:30:00Z | SID:S03 | VAL:99.9
LOG_TIME:2023-10-15T10:44:59Z | SID:S03 | VAL:100.1
LOG_TIME:2023-10-15T11:00:00Z | SID:S01 | VAL:50.0
EOF

    chmod -R 777 /home/user
