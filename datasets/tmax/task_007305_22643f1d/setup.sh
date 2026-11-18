#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/uptime_monitor.py
import sys
import os

def parse_log_line(line):
    line = line.strip()
    if not line: return None
    # BUG: splits on all '|', failing if message contains '|'
    timestamp, service, status, message = line.split('|')
    return timestamp, service, status, message

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python uptime_monitor.py <logfile>")
        sys.exit(1)

    with open(sys.argv[1], 'r') as f:
        for line in f:
            parsed = parse_log_line(line)
            if parsed:
                print(parsed)
EOF

    cat << 'EOF' > /home/user/logs/web.log
2023-11-01 10:00:01|web|UP|Starting web server
2023-11-01 10:05:22|web|UP|User requested path /login
2023-11-01 10:15:00|web|DOWN|Unhandled exception: User typed a | in the username field
2023-11-01 10:16:05|web|UP|Web server restarted successfully
EOF

    cat << 'EOF' > /home/user/logs/db.log
2023-11-01 10:00:00|db|UP|Database initialized
2023-11-01 10:05:23|db|UP|Query executed successfully
2023-11-01 10:15:01|db|UP|Connection lost from web service
2023-11-01 10:16:06|db|UP|Connection established from web service
EOF

    cat << 'EOF' > /home/user/logs/cache.log
2023-11-01 10:00:02|cache|UP|Redis cache started
2023-11-01 10:05:23|cache|UP|Cache miss for user session
2023-11-01 10:12:00|cache|UP|Evicting old keys | count=450
2023-11-01 10:16:06|cache|UP|Cache hit for user session
EOF

    chmod -R 777 /home/user
