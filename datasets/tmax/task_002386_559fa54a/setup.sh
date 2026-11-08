#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/app.log
2023-10-01T10:00:00Z|INFO|{"event": "login", "user": "alice"}
2023-10-01T10:05:00Z|WARN|{"event": "retry", "user": "bob"}
2023-10-01T10:10:00Z|INFO|{"event": "message", "text": "hello | world", "user": "alice"}
2023-10-01T10:15:00Z|INFO|{"event": "logout", "user": "alice"}
2023-10-01T10:20:00Z|ERROR|{"event": "crash", "reason": "pipe | exception | caught"}
EOF

    cat << 'EOF' > /home/user/process_logs.py
import sys
import json

def process_file(filepath):
    valid_records = 0
    error_records = 0
    with open(filepath, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line: continue
            try:
                # Bug: split('|') splits on all pipes, destroying JSON with pipes inside
                parts = line.split('|')
                timestamp = parts[0]
                level = parts[1]
                payload = parts[2]

                data = json.loads(payload)
                valid_records += 1
            except Exception as e:
                print(f"Error on line {line_num}: {e}")
                error_records += 1

    return valid_records, error_records

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python process_logs.py <logfile>")
        sys.exit(1)

    v, e = process_file(sys.argv[1])

    with open("/home/user/diagnostic_summary.json", "w") as out:
        json.dump({"valid": v, "errors": e}, out)
EOF

    chmod -R 777 /home/user
