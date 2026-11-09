#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/ticket_8412

    cat << 'EOF' > /home/user/ticket_8412/container_logs.txt
[2023-10-12 10:00:00] [INFO] Service started successfully
[2023-10-12 10:01:15] [DEBUG] Connecting to database at localhost:5432
[2023-10-12 10:02:30] [ERROR] Connection lost - retrying in 5s
[2023-10-12 10:05:00] [WARN] [AuthService] Failed login attempt for user [admin]
[2023-10-12 10:06:00] [INFO] Service stopped
EOF

    cat << 'EOF' > /home/user/ticket_8412/parser.py
import json
import sys

def parse_line(line):
    if not line.strip(): return None
    # Parse format: [TIMESTAMP] [LEVEL] MESSAGE
    parts = line.strip().split('] [')
    timestamp = parts[0].strip('[')
    level, msg = parts[1].split('] ')
    return {"time": timestamp, "level": level, "message": msg}

def main():
    input_file = sys.argv[1]
    output_file = sys.argv[2]

    with open(input_file, 'r') as f, open(output_file, 'w') as out:
        for line in f:
            parsed = parse_line(line)
            if parsed:
                out.write(json.dumps(parsed) + '\n')

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/ticket_8412/parser.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
