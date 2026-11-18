#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    git init
    git config user.name "Support Admin"
    git config user.email "admin@example.com"

    export GIT_COMMITTER_DATE="2024-01-01T10:00:00Z"
    export GIT_AUTHOR_DATE="2024-01-01T10:00:00Z"

    # Commit 1: Good (Handles N/A correctly)
    cat << 'EOF' > process_data.py
import sys

def process(file_path):
    total = 0.0
    count = 0
    with open(file_path, 'r') as f:
        for line in f:
            val = line.strip().split(',')[1]
            if val == "N/A":
                continue
            total += float(val)
            count += 1
    return total / count if count else 0

if __name__ == "__main__":
    print(process(sys.argv[1]))
EOF
    git add process_data.py
    git commit -m "Initial working version"
    git tag v1.0

    # Commit 2: Good (Refactoring)
    export GIT_COMMITTER_DATE="2024-01-02T10:00:00Z"
    export GIT_AUTHOR_DATE="2024-01-02T10:00:00Z"
    cat << 'EOF' > process_data.py
import sys

def parse_val(val):
    if val == "N/A":
        return None
    return float(val)

def process(file_path):
    total = 0.0
    count = 0
    with open(file_path, 'r') as f:
        for line in f:
            parsed = parse_val(line.strip().split(',')[1])
            if parsed is not None:
                total += parsed
                count += 1
    return total / count if count else 0

if __name__ == "__main__":
    print(process(sys.argv[1]))
EOF
    git add process_data.py
    git commit -m "Refactor parsing logic"

    # Commit 3: BAD (Removes N/A handling, causing ValueError on N/A)
    export GIT_COMMITTER_DATE="2024-01-03T10:00:00Z"
    export GIT_AUTHOR_DATE="2024-01-03T10:00:00Z"
    cat << 'EOF' > process_data.py
import sys

def parse_val(val):
    # Performance optimization: remove N/A check, assume clean data
    return float(val)

def process(file_path):
    total = 0.0
    count = 0
    with open(file_path, 'r') as f:
        for line in f:
            parsed = parse_val(line.strip().split(',')[1])
            total += parsed
            count += 1
    return total / count if count else 0

if __name__ == "__main__":
    print(process(sys.argv[1]))
EOF
    git add process_data.py
    git commit -m "Optimize parsing by assuming clean data"

    # Commit 4: BAD (Add irrelevant feature)
    export GIT_COMMITTER_DATE="2024-01-04T10:00:00Z"
    export GIT_AUTHOR_DATE="2024-01-04T10:00:00Z"
    echo "# added EOF comment" >> process_data.py
    git add process_data.py
    git commit -m "Add EOF comment"

    # Create the input data file
    cat << 'EOF' > /home/user/sensor_data.csv
1700000001,22.5
1700000002,22.6
1700000003,22.4
1700000004,22.7
1700000005,N/A
1700000006,22.8
1700000007,22.9
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
