#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/writer.py
import time
import os

log_file = '/home/user/uptime_metrics.log'
with open(log_file, 'w') as f:
    f.write('{"host": "web-01", "uptime_ms": 5000}\n')
    f.write('{"host": "web-02", "uptime_ms": 7500}\n')
    f.write('{"host": "db-01", "uptime_ms": 12000}\n')
    f.write('FATAL: kernel panic - not syncing\n') # Corrupted line
    f.write('{"host": "cache-01", "uptime_ms": NaN}\n') # Invalid JSON
    f.write('{"host": "web-03", "uptime_ms": 3000}\n')
    f.flush()

    # Hold the file open
    time.sleep(100000)
EOF

    cat << 'EOF' > /home/user/aggregate_uptime.py
import sys
import json

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 aggregate_uptime.py <logfile>")
        sys.exit(1)

    log_file = sys.argv[1]
    total_uptime = 0

    with open(log_file, 'r') as f:
        for line in f:
            data = json.loads(line.strip())
            total_uptime += data['uptime_ms']

    with open('/home/user/total_uptime.json', 'w') as f:
        json.dump({"total_uptime_ms": total_uptime}, f)

if __name__ == "__main__":
    main()
EOF

    # Create a startup script to run the background process when the container is executed
    mkdir -p /.singularity.d/env
    cat << 'EOF' > /.singularity.d/env/99-startup.sh
if ! pgrep -f writer.py > /dev/null 2>&1; then
    python3 /home/user/writer.py &
    sleep 1
    rm -f /home/user/uptime_metrics.log
fi
EOF
    chmod +x /.singularity.d/env/99-startup.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
