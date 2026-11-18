#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/system_a.log
2023-10-01T10:00:00Z main_service 45
2023-10-01T10:01:00Z auth_service 12
EOF

    cat << 'EOF' > /home/user/logs/system_b.log
2023-10-01T10:02:00Z db_service 99
2023-10-01T10:03:00Z cache service 4
2023-10-01T10:04:00Z api_service 15
EOF

    cat << 'EOF' > /home/user/profiler.py
import sys
import glob

def process_logs():
    files = glob.glob('/home/user/logs/*.log')
    files.sort()
    for f in files:
        with open(f, 'r') as fd:
            for line in fd:
                parts = line.strip().split()
                # Crash happens here when parts has > 3 items due to space in name
                assert len(parts) >= 3, "Invalid log line"
                timestamp = parts[0]
                service = parts[1]
                metric = int(parts[2])

if __name__ == '__main__':
    process_logs()
EOF

    python3 -m py_compile /home/user/profiler.py
    mv /home/user/__pycache__/profiler.*.pyc /home/user/profiler.pyc
    rm -rf /home/user/__pycache__

    python3 /home/user/profiler.pyc 2> /home/user/crash.log || true

    rm /home/user/profiler.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
