#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    # 1. Setup repo and git history
    mkdir -p /home/user/sim_repo
    cd /home/user/sim_repo
    git init

    # Configure git
    git config user.name "DevOps"
    git config user.email "devops@example.com"

    # Create conflicting requirements.txt
    cat << 'EOF' > requirements.txt
numpy==1.24.3
requests==2.28.1
urllib3>=2.0.0
EOF

    # Create base sim.py (Good Version)
    cat << 'EOF' > sim.py
import math

def run_simulation():
    # Good version uses integer math for indices to avoid precision loss
    steps = 100
    arr = [0] * 101
    current_val = 0.0

    for i in range(steps):
        current_val += 0.01

    # Correct calculation: using round prevents float precision issues (0.9999999999999999)
    idx = int(round(current_val * 100))
    arr[idx] = 1
    print("Success")

if __name__ == "__main__":
    run_simulation()
EOF

    git add requirements.txt sim.py
    git commit -m "Initial commit: working simulation"

    # Couple of good commits
    echo "# comment 1" >> sim.py
    git commit -am "Update comments"
    echo "# comment 2" >> sim.py
    git commit -am "Add more docs"

    # Bad commit: Introduces precision loss
    cat << 'EOF' > sim.py
import math

def run_simulation():
    steps = 100
    arr = [0] * 100  # off-by-one boundary condition setup
    current_val = 0.0

    for i in range(steps):
        current_val += 0.01

    # Bad calculation: int() truncates 0.9999999999999999 to 0 instead of 1. Wait, 100 * 0.01 is 1.0. 
    # Actually, let's make it explicitly fail.
    # 100 * 0.01 is 1.0. If arr is size 100, valid indices are 0-99.
    # We want precision loss to cause out of bounds.
    # If current_val = 1.0000000000000007 (due to float addition), current_val * 100 = 100.00000000000007
    # int() makes it 100. arr size 100 -> index 100 is out of bounds!
    idx = int(current_val * 100)
    arr[idx] = 1
    print("Success")

if __name__ == "__main__":
    run_simulation()
EOF
    git commit -am "Optimize calculation logic"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Couple of more bad commits
    echo "# comment 3" >> sim.py
    git commit -am "Minor formatting"
    echo "# comment 4" >> sim.py
    git commit -am "Update logging"

    # 2. Setup memory dump
    mkdir -p /home/user/logs
    dd if=/dev/urandom of=/home/user/logs/dump.bin bs=1K count=1 2>/dev/null
    echo -n "PANIC_LOG:BOUNDARY_EXCEEDED_AT_INDEX_100_DUE_TO_FLOAT_TRUNCATION" >> /home/user/logs/dump.bin
    dd if=/dev/urandom bs=1K count=1 2>/dev/null >> /home/user/logs/dump.bin

    # Save the expected JSON for validation
    cat << EOF > /tmp/expected_resolution.json
{
  "bad_commit": "$BAD_COMMIT",
  "panic_string": "PANIC_LOG:BOUNDARY_EXCEEDED_AT_INDEX_100_DUE_TO_FLOAT_TRUNCATION"
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
