#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/requirements.txt
requests==2.25.1
urllib3==1.20
EOF

    cat << 'EOF' > /home/user/data.txt
0.1
0.2
0.3
0.1
0.2
0.3
EOF

    cat << 'EOF' > /home/user/calc.py
import sys

def calculate_total(file_path):
    with open(file_path, 'r') as f:
        lines = f.readlines()

    total = 0.0
    # Off-by-one error: skips the first line
    for i in range(1, len(lines)):
        val = float(lines[i].strip())
        total += val

    with open('/home/user/output.txt', 'w') as f:
        f.write(f"{total}")

if __name__ == '__main__':
    calculate_total('/home/user/data.txt')
EOF

    chmod -R 777 /home/user
