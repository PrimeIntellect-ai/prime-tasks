#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/builder.py
#!/usr/bin/env python3
import math

def compute_decay_table(n):
    table = []
    # Bug 1: Off-by-one and incorrect boundary. Starts at 1, ends at n-1.
    for i in range(1, n):
        # Bug 2: Precision loss due to floor and scaling
        val = math.floor(math.exp(-i / 10.0) * 100) / 100.0
        table.append(val)
    return table

def main():
    n = 50
    table = compute_decay_table(n)

    # Causes IndexError because length is 49 (indices 0-48) but requests index 49
    last_val = table[n-1]

    with open("/home/user/decay_table.txt", "w") as f:
        for v in table:
            f.write(f"{v:.6f}\n")

if __name__ == "__main__":
    main()
EOF

    chmod +x /home/user/builder.py
    chmod -R 777 /home/user
