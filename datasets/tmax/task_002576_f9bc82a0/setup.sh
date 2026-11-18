#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip strace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the hidden secret factor
    echo "100" > /home/user/.secret_factor

    # Create the suspicious script
    cat << 'EOF' > /home/user/suspicious_math.py
import sys

def process(target_file):
    try:
        with open('/home/user/.secret_factor', 'r') as f:
            factor = int(f.read().strip())
    except FileNotFoundError:
        factor = 1

    try:
        with open(target_file, 'r') as f:
            lines = [int(x.strip()) for x in f.readlines() if x.strip()]
    except Exception:
        sys.exit(0)

    accumulator = factor
    flag1 = False
    flag2 = False

    for val in lines:
        if val == 42:
            flag1 = True
        elif val == 17 and flag1:
            flag2 = True
        elif val == 99 and flag2:
            # Crash
            x = 1 / (val - 99)

        accumulator = (accumulator + val) % 10000

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(0)
    process(sys.argv[1])
EOF

    # Create the large payload
    python3 -c "
import random
random.seed(123)
with open('/home/user/large_payload.txt', 'w') as f:
    for i in range(50):
        if i == 12: f.write('42\n')
        elif i == 25: f.write('17\n')
        elif i == 38: f.write('99\n')
        else: f.write(f'{random.randint(1, 98)}\n')
"

    chmod -R 777 /home/user
