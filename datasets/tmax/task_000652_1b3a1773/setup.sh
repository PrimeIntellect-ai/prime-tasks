#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server_logs.txt
[INFO] 2023-10-25T21:00:00Z User login
[ERROR] 2023-10-25T22:30:00+0000 Database timeout
[INFO] 2023-10-26T01:30:00+0300 User logout
[WARN] 2023-10-25T23:45:00.123Z High memory usage
[INFO] 2023-10-26T00:10:00Z System update
EOF

    cat << 'EOF' > /home/user/log_analyzer.py
import sys
import json
from datetime import datetime, timezone

def parse_log_line(line):
    parts = line.split(']', 1)
    if len(parts) != 2: return None
    level = parts[0][1:]
    rest = parts[1].strip()
    ts_str, msg = rest.split(' ', 1)

    if ts_str.endswith('Z'):
        ts_str = ts_str[:-1] + '+0000'

    dt = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%S%z")
    return dt, level, msg

def main():
    target_date = "2023-10-25"
    results = []
    with open('/home/user/server_logs.txt', 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue

            dt, level, msg = parse_log_line(line)

            # Filter by date
            if dt.date().isoformat() == target_date:
                results.append({"timestamp": dt.isoformat(), "level": level, "message": msg})

    with open('/home/user/results.json', 'w') as f:
        json.dump(results, f, indent=2)

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /home/user/run_test.sh
#!/bin/bash
python3 /home/user/log_analyzer.py
if [ $? -ne 0 ]; then
    echo "Build Failed: Script crashed."
    exit 1
fi

COUNT=$(jq '. | length' /home/user/results.json)
if [ "$COUNT" -ne 4 ]; then
    echo "Build Failed: Expected 4 events for 2023-10-25, found $COUNT."
    exit 1
fi
echo "Build Passed."
EOF

    chmod +x /home/user/run_test.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
