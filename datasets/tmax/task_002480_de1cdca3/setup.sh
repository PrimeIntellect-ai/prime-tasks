#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/access_01.log
192.168.1.1 [10/Oct/2023:13:55:36] "GET /index.html HTTP/1.1" 200 1024
192.168.1.2 [10/Oct/2023:13:56:01] "POST /api/login HTTP/1.1" 200 512
192.168.1.3 [10/Oct/2023:13:57:11] "GET /images/logo.png HTTP/1.1" 304 0
EOF

    cat << 'EOF' > /home/user/logs/access_02.log
10.0.0.5 [12/Nov/2023:03:10:00] "GET /dashboard HTTP/1.1" 200 2048
10.0.0.6 [12/Nov/2023:03:12:45] "GET /assets/app.js HTTP/1.1" 200 4096
10.0.0.5 [12/Nov/2023:03:14:15] "GET /weird path with spaces HTTP/1.1" 404 532
10.0.0.8 [12/Nov/2023:03:15:00] "GET /logout HTTP/1.1" 302 0
EOF

    cat << 'EOF' > /home/user/process_logs.py
import sys
import os

def process_file(filepath):
    with open(filepath, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line: continue

            # Flawed parsing logic: assumes no spaces inside the URI
            parts = line.split(" ")
            if len(parts) < 6:
                continue

            ip = parts[0]
            date = parts[1]
            method = parts[2].strip('"')
            uri = parts[3]
            protocol = parts[4].strip('"')

            # This will crash if parts[5] is not the status code 
            # (e.g., if there were spaces in the URI)
            status = int(parts[5])

            # Dummy processing
            if status >= 500:
                pass

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python process_logs.py <log_file>")
        sys.exit(1)

    if os.path.isdir(sys.argv[1]):
        for filename in os.listdir(sys.argv[1]):
            process_file(os.path.join(sys.argv[1], filename))
    else:
        process_file(sys.argv[1])
EOF

    chmod +x /home/user/process_logs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
