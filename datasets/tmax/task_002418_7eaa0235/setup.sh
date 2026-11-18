#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip docker.io curl
    pip3 install pytest

    mkdir -p /app/obs-dash-gen

    cat << 'EOF' > /app/obs-dash-gen/main.py
import sys
from parser import parse_logs

def main():
    if len(sys.argv) < 2:
        print("Usage: python main.py <logfile>")
        sys.exit(1)

    logfile = sys.argv[1]
    logs = parse_logs(logfile)

    print("<html><body><h1>Dashboard</h1><ul>")
    for log in logs[:100]:
        print(f"<li>{log}</li>")
    print("</ul></body></html>")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /app/obs-dash-gen/parser.py
import re

def parse_logs(filepath):
    # Faulty regex causing catastrophic backtracking on malformed lines
    pattern = re.compile(r'^(.*)-(.*)-(.*)-(\d+)-(.*)$')
    parsed = []
    with open(filepath, 'r') as f:
        for line in f:
            match = pattern.match(line.strip())
            if match:
                parsed.append(match.groups())
    return parsed
EOF

    cat << 'EOF' > /app/obs-dash-gen/requirements.txt
# No external dependencies required
EOF

    useradd -m -s /bin/bash user || true

    python3 -c '
with open("/home/user/system.log", "w") as f:
    for i in range(50000):
        if i % 500 == 0:
            # Malformed line to cause backtracking
            f.write("a-" * 50 + "b\n")
        else:
            f.write("INFO-app-module-123-message\n")
'

    chmod -R 777 /home/user
