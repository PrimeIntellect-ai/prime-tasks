#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest

    # Install Rust
    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    chmod -R 777 /opt/rust
    export PATH="/opt/rust/bin:${PATH}"

    mkdir -p /home/user/
    cat << 'EOF' > /home/user/legacy.c
#include <stdio.h>
int main() { printf("Vulnerable legacy C code\n"); return 0; }
EOF

    cat << 'EOF' > /home/user/generate_dataset.py
import random

def generate_expr(depth=0):
    if depth > 3 or random.random() < 0.4:
        return str(random.randint(1, 10))

    op = random.choice(['add', 'sub', 'mul', 'div'])
    left = generate_expr(depth + 1)
    right = generate_expr(depth + 1)

    # Intentionally create some div-by-zero for security testing
    if op == 'div' and random.random() < 0.2:
        right = "0"

    return f"{op}({left}, {right})"

random.seed(42)
with open("/home/user/dataset.txt", "w") as f:
    for _ in range(1000):
        f.write(generate_expr() + "\n")
EOF
    python3 /home/user/generate_dataset.py

    cat << 'EOF' > /tmp/solve.py
import re

def parse_and_eval(expr):
    # simple recursive descent
    def parse(s, idx):
        if idx >= len(s): return None, idx
        if s[idx].isdigit() or s[idx] == '-':
            start = idx
            while idx < len(s) and (s[idx].isdigit() or s[idx] == '-'):
                idx += 1
            return int(s[start:idx]), idx

        for op in ['add', 'sub', 'mul', 'div']:
            if s.startswith(op, idx):
                idx += 3
                if s[idx] != '(': return None, idx
                idx += 1
                left, idx = parse(s, idx)
                if left is None: return None, idx
                if s[idx] != ',': return None, idx
                idx += 1
                while s[idx] == ' ': idx += 1
                right, idx = parse(s, idx)
                if right is None: return None, idx
                if s[idx] != ')': return None, idx
                idx += 1

                if op == 'add': return left + right, idx
                if op == 'sub': return left - right, idx
                if op == 'mul': return left * right, idx
                if op == 'div':
                    if right == 0: raise ValueError("div by zero")
                    return int(left / right), idx
        return None, idx

    try:
        s = expr.replace(" ", "")
        res, idx = parse(s, 0)
        if idx == len(s): return res
        return None
    except:
        return None

total = 0
with open("/home/user/dataset.txt", "r") as f:
    for line in f:
        res = parse_and_eval(line.strip())
        if res is not None:
            total += res

with open("/tmp/expected_sum.txt", "w") as f:
    f.write(str(total))
EOF
    python3 /tmp/solve.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
