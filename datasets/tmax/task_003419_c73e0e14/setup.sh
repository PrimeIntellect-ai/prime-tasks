#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip locales logrotate
    pip3 install --default-timeout=100 pytest

    # Create oracle program
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/log-router-oracle
#!/usr/bin/env python3
import sys
import re

def process(file_path):
    with open(file_path, 'r') as f:
        for line in f:
            if re.search(r'Disconnecting: Too many authentication failures', line):
                print(f"ROUTING_DIRECTIVE: REJECT {line.strip()} OFFSET: +0100")
            else:
                print(f"ROUTING_DIRECTIVE: ACCEPT {line.strip()} OFFSET: +0100")

if __name__ == "__main__":
    process(sys.argv[1])
EOF
    chmod +x /opt/oracle/log-router-oracle

    # Create vendored package
    mkdir -p /app/log-router-v1.2/src
    cat << 'EOF' > /app/log-router-v1.2/src/parser.py
import re

def parse_line(line):
    if re.search(r'Disconnecting: Too many failures', line):
        status = "REJECT"
    else:
        status = "ACCEPT"

    offset = "+0200"

    return f"ROUTING_DIRECTIVE: {status} {line.strip()} OFFSET: {offset}"
EOF

    cat << 'EOF' > /app/log-router-v1.2/src/main.py
import sys
from parser import parse_line

def main():
    with open(sys.argv[1], 'r') as f:
        for line in f:
            print(parse_line(line))

if __name__ == "__main__":
    main()
EOF

    # Setup user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logs
    chmod -R 777 /home/user
