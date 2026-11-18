#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y software-properties-common git
    add-apt-repository ppa:deadsnakes/ppa
    apt-get update
    apt-get install -y python3.9 python3.9-distutils python3-pip

    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1
    update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1

    python3 -m pip install --upgrade pip
    python3 -m pip install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_service
    cd /home/user/log_service

    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    cat << 'EOF' > requirements.txt
# Conflict: requires exact version
pyyaml==6.0
EOF

    cat << 'EOF' > test_leak.py
import sys
import tracemalloc
from parser import process_logs

def main():
    if len(sys.argv) < 2:
        print("Usage: python test_leak.py <logfile>")
        sys.exit(2)

    tracemalloc.start()
    with open(sys.argv[1], 'r') as f:
        lines = f.readlines()

    process_logs(lines)

    current, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()

    # If peak memory is over 1MB for this small log file, we have a leak
    if peak > 1000000:
        print(f"LEAK DETECTED! Peak memory: {peak} bytes")
        sys.exit(1)
    else:
        print("No leak detected.")
        sys.exit(0)

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > parser.py
def process_logs(log_lines):
    parsed = []
    for line in log_lines:
        line = line.strip()
        if not line: continue
        # Simple parsing
        parsed.append({"raw": line, "status": "processed"})
    return parsed
EOF

    git add requirements.txt test_leak.py parser.py
    git commit -m "Initial commit: basic parser"
    GOOD_COMMIT=$(git rev-parse HEAD)

    for i in {1..3}; do
        echo "# feature $i" >> parser.py
        git commit -am "Added feature $i"
    done

    cat << 'EOF' > parser.py
error_cache = []

def process_logs(log_lines):
    parsed = []
    for line in log_lines:
        line = line.strip()
        if not line: continue

        if "CORRUPTED_ENTRY" in line:
            # Memory leak: unbounded append of massive strings
            error_cache.append(line * 10000)
            continue

        parsed.append({"raw": line, "status": "processed"})
    return parsed
EOF
    git commit -am "Added error caching for corrupted entries"
    BAD_COMMIT=$(git rev-parse HEAD)

    for i in {4..6}; do
        echo "# feature $i" >> parser.py
        git commit -am "Added feature $i"
    done

    echo $BAD_COMMIT > /home/user/.truth_bad_commit

    cd /home/user
    cat << 'EOF' > generate_logs.py
import random
with open("suspicious_logs.txt", "w") as f:
    for i in range(500):
        f.write(f"INFO: Log entry {i} standard operation\n")
    # The corrupted line
    f.write("WARN: [ID:999] CORRUPTED_ENTRY parse_failure_0x88\n")
    for i in range(500, 1000):
        f.write(f"INFO: Log entry {i} standard operation\n")
EOF
    python3 generate_logs.py
    rm generate_logs.py

    python3 -m pip install pyyaml==5.4.1

    chown -R user:user /home/user
    chmod -R 777 /home/user
