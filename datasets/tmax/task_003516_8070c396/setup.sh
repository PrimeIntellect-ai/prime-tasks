#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python-is-python3 git
    pip3 install pytest numpy

    mkdir -p /home/user/trade_pipeline
    cd /home/user/trade_pipeline
    git init
    git config user.name "OnCall Dev"
    git config user.email "dev@example.com"

    # Create dummy input data
    cat << 'EOF' > trades.csv
trade_id,value
1,10000000.12345
2,20000000.23456
3,30000000.34567
EOF

    # Create validation script
    cat << 'EOF' > validate_run.py
import subprocess
import sys

try:
    output = subprocess.check_output(["python", "aggregate.py"], text=True)
    expected = 60000000.70368
    actual = float(output.strip())
    if abs(expected - actual) > 0.001:
        print(f"Precision loss detected: Expected {expected}, got {actual}")
        sys.exit(1)
    else:
        print("Valid run.")
        sys.exit(0)
except Exception as e:
    print("Execution failed.")
    sys.exit(1)
EOF

    # Create base aggregate script (Good)
    cat << 'EOF' > aggregate.py
import numpy as np
import csv

def run():
    total_exposure = np.float64(0.0)
    with open('trades.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            total_exposure += np.float64(row['value'])
    print(total_exposure)

if __name__ == "__main__":
    run()
EOF

    git add .
    git commit -m "Initial commit with working pipeline"
    git tag v1.0

    # Add a harmless commit
    echo "# Trade Aggregation" > README.md
    git add README.md
    git commit -m "Add README"

    # Add another harmless commit
    cat << 'EOF' > .gitignore
*.pyc
__pycache__
EOF
    git add .gitignore
    git commit -m "Add gitignore"

    # BAD COMMIT: Introduce precision loss
    cat << 'EOF' > aggregate.py
import numpy as np
import csv

def run():
    total_exposure = np.float32(0.0)
    with open('trades.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            total_exposure += np.float32(row['value'])
    print(total_exposure)

if __name__ == "__main__":
    run()
EOF
    git add aggregate.py
    git commit -m "Optimize memory usage by downcasting accumulators"
    BAD_COMMIT_HASH=$(git rev-parse HEAD)

    # Another harmless commit
    echo "Update" >> README.md
    git add README.md
    git commit -m "Update docs"

    # Save the bad commit hash for verification
    echo "$BAD_COMMIT_HASH" > /tmp/expected_bad_commit.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
