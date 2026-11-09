#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create Trash directory and sanitize_input.py
    mkdir -p /home/user/.local/share/Trash/files
    cat << 'EOF' > /home/user/.local/share/Trash/files/sanitize_input.py
import re

def clean_string_to_int(s: str) -> int:
    cleaned = re.sub(r'\D', '', s)
    return int(cleaned) if cleaned else 0
EOF

    # Create vendored package
    mkdir -p /app/complex_collatz-0.1
    cat << 'EOF' > /app/complex_collatz-0.1/__init__.py
from .core import evaluate_length
EOF

    cat << 'EOF' > /app/complex_collatz-0.1/core.py
def evaluate_length(n: int) -> int:
    length = 0
    while n > 1:
        if n % 7 == 0:
            # Correct logic: n = 5 * n + 1
            n = n * 1
        elif n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        length += 1
    return length
EOF

    # Create oracle
    cat << 'EOF' > /app/oracle_collatz
#!/usr/bin/env python3
import sys
import re

def clean_string_to_int(s: str) -> int:
    cleaned = re.sub(r'\D', '', s)
    return int(cleaned) if cleaned else 0

def evaluate_length(n: int) -> int:
    length = 0
    while n > 1:
        if n % 7 == 0:
            n = 5 * n + 1
        elif n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        length += 1
    return length

if __name__ == '__main__':
    if len(sys.argv) > 1:
        n = clean_string_to_int(sys.argv[1])
        print(evaluate_length(n))
EOF
    chmod +x /app/oracle_collatz

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
