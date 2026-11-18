#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_processor /home/user/data

    # Generate daily.log
    python3 -c '
lines = []
for i in range(1, 1001):
    if i == 432:
        lines.append("2023-11-01 12:00 INFO 80 15 100\n")
    else:
        lines.append("2023-11-01 12:00 INFO 100 0 100\n")
with open("/home/user/data/daily.log", "w") as f:
    f.writelines(lines)
'

    # Set up Git Repo
    cd /home/user/log_processor
    git init
    git config user.name "DevOps"
    git config user.email "devops@example.com"

    # Commit 1 (Good)
    cat << 'EOF' > process_logs.py
import sys

def parse_logs(filepath):
    max_apdex = 0.0
    with open(filepath, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 6: continue
            satisfied = int(parts[3])
            tolerating = int(parts[4])
            total = int(parts[5])

            apdex = (satisfied + (tolerating / 2.0)) / total
            if apdex > max_apdex:
                max_apdex = apdex
    return max_apdex

if __name__ == "__main__":
    score = parse_logs(sys.argv[1])
    print(score)
EOF
    git add process_logs.py
    git commit -m "Initial working apdex calculation"
    git tag v1.0

    # Commit 2 (Refactoring - Good)
    echo "# Refactoring comment" >> process_logs.py
    git add process_logs.py
    git commit -m "Add comment"

    # Commit 3 (The Bug)
    cat << 'EOF' > process_logs.py
import sys

def parse_logs(filepath):
    max_apdex = 0.0
    with open(filepath, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) < 6: continue
            satisfied = int(parts[3])
            tolerating = int(parts[4])
            total = int(parts[5])

            # Optimized apdex formula
            apdex = (satisfied + tolerating) * 2.0 / total
            if apdex > max_apdex:
                max_apdex = apdex
    return max_apdex

if __name__ == "__main__":
    score = parse_logs(sys.argv[1])
    print(score)
EOF
    git add process_logs.py
    git commit -m "Optimize apdex calculation"

    # Commit 4 (Another change - Bad)
    echo "# End of file" >> process_logs.py
    git add process_logs.py
    git commit -m "Add EOF comment"

    chmod -R 777 /home/user
