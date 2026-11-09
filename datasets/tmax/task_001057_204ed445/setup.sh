#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/diagnostics /home/user/logs

    cat << 'EOF' > "/home/user/logs/app err 1.log"
ERROR_ID: E101
Caused by: E102
ERROR_ID: E102
Caused by: E103
ERROR_ID: E103
EOF

    cat << 'EOF' > "/home/user/logs/app err 2.log"
ERROR_ID: E201
Caused by: E202
ERROR_ID: E202
Caused by: E201
EOF

    cat << 'EOF' > "/home/user/logs/sys log 3.log"
ERROR_ID: E301
Caused by: E302
ERROR_ID: E302
EOF

    cat << 'EOF' > "/home/user/logs/db err 4.log"
ERROR_ID: E401
Caused by: E402
ERROR_ID: E402
Caused by: E403
ERROR_ID: E403
Caused by: E401
EOF

    cat << 'EOF' > "/home/user/logs/net log 5.log"
ERROR_ID: E501
EOF

    cat << 'EOF' > /home/user/diagnostics/run_pipeline.sh
#!/bin/bash
# Bug 1: Unquoted variables and bad for-loop over ls breaks on spaces
for file in $(ls /home/user/logs/*.log); do
    python3 /home/user/diagnostics/parse_trace.py "$file" &
done
wait
EOF
    chmod +x /home/user/diagnostics/run_pipeline.sh

    cat << 'EOF' > /home/user/diagnostics/parse_trace.py
import sys
import json
import time
import fcntl
import os

def parse_log(filepath):
    errors = {}
    first_error = None
    with open(filepath, 'r') as f:
        lines = f.readlines()

    current_id = None
    for line in lines:
        line = line.strip()
        if line.startswith("ERROR_ID:"):
            current_id = line.split(":")[1].strip()
            if first_error is None:
                first_error = current_id
            if current_id not in errors:
                errors[current_id] = None
        elif line.startswith("Caused by:") and current_id:
            cause_id = line.split(":")[1].strip()
            errors[current_id] = cause_id

    return first_error, errors

# Bug 2: Infinite recursion on circular references
def find_root_cause(errors, current_id):
    cause = errors.get(current_id)
    if cause:
        return find_root_cause(errors, cause)
    return current_id

def main():
    if len(sys.argv) < 2:
        return

    filepath = sys.argv[1]
    first_error, errors = parse_log(filepath)

    if not first_error:
        return

    root_cause = find_root_cause(errors, first_error)

    report_file = '/home/user/diagnostics/report.json'

    # Bug 3: Race condition (read-modify-write without locking)
    if not os.path.exists(report_file):
        with open(report_file, 'w') as f:
            json.dump([], f)

    with open(report_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = []

    time.sleep(0.1) # Exacerbate race condition

    data.append({
        "file": os.path.basename(filepath),
        "root_cause": root_cause
    })

    with open(report_file, 'w') as f:
        json.dump(data, f, indent=2)

if __name__ == "__main__":
    main()
EOF
    chmod +x /home/user/diagnostics/parse_trace.py

    chmod -R 777 /home/user
