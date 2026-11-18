#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        e2fsprogs \
        e2tools \
        git

    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create equation.png
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 32 -fill black \
        -draw "text 50,100 'PARAMETERS: ALPHA=0.125 BETA=0.015625'" /app/equation.png

    # Create workspace.img and simulate deleted file
    dd if=/dev/zero of=/app/workspace.img bs=1M count=10
    mkfs.ext4 /app/workspace.img

    cat << 'EOF' > /tmp/test_runner.py
import sys
from sim import compute_state
# Usage: test_runner.py <alpha> <beta>
inputs = [float(x) for x in sys.stdin.read().split()]
res = compute_state(inputs, float(sys.argv[1]), float(sys.argv[2]))
print(res)
EOF

    e2cp /tmp/test_runner.py /app/workspace.img:/
    e2rm /app/workspace.img:/test_runner.py

    # Create git repository
    mkdir -p /home/user/sim_repo
    cd /home/user/sim_repo
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > sim.py
import math
def compute_state(inputs, alpha, beta):
    return math.fsum(v * alpha - (v**2) * beta for v in inputs)
EOF
    git add sim.py
    git commit -m "Initial commit"

    for i in $(seq 1 100); do
        echo "# Good commit $i" >> sim.py
        git commit -am "Good commit $i"
    done

    cat << 'EOF' > sim.py
import math
def compute_state(inputs, alpha, beta):
    res = 0.0
    for v in inputs:
        res += v * alpha - (v**2) * beta
    return res
EOF
    git commit -am "Refactor compute_state for performance"

    for i in $(seq 1 99); do
        echo "# Another commit $i" >> sim.py
        git commit -am "Another commit $i"
    done

    # Create oracle.py
    cat << 'EOF' > /app/oracle.py
import sys
import math

def main():
    ALPHA = 0.125
    BETA = 0.015625
    data = sys.stdin.read().split()
    if not data:
        print(0.0)
        return
    inputs = [float(x) for x in data]
    res = math.fsum(v * ALPHA - (v**2) * BETA for v in inputs)
    print(repr(res))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
