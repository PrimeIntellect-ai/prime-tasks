#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/uptime.jsonl
{"url": "site1.com", "uptime": 99}
{"url": "site2.com", "uptime": 98
{"url": "site3.com", "uptime": 100}
EOF

    cat << 'EOF' > /home/user/run_processor.sh
#!/bin/bash
export TIMEOUT_SECS="5s"
python3 /home/user/process_logs.py
EOF
    chmod +x /home/user/run_processor.sh

    cat << 'EOF' > /home/user/process_logs.py
import json
import os

def main():
    timeout = int(os.environ.get('TIMEOUT_SECS', 10))
    valid_count = 0
    with open('/home/user/uptime.jsonl', 'r') as f:
        for line in f:
            data = json.loads(line)
            valid_count += 1
    print(f"Processed {valid_count} valid logs with timeout {timeout}")

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
