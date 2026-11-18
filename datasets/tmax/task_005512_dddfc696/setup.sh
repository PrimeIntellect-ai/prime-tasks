#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_calc.py
import sys

def evaluate_rpn(expression):
    stack = []
    tokens = expression.split()
    for token in tokens:
        if token in ['+', '-', '*', '/', '%']:
            b = stack.pop()
            a = stack.pop()
            if token == '+': stack.append(a + b)
            elif token == '-': stack.append(a - b)
            elif token == '*': stack.append(a * b)
            elif token == '/': stack.append(a // b)
            elif token == '%': stack.append(a % b)
        else:
            stack.append(int(token))
    return stack[0]

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print evaluate_rpn(sys.argv[1])
EOF

    cat << 'EOF' > /home/user/test_cases.tsv
2 3 +	5
10 5 /	2
7 3 %	1
5 1 2 + 4 * + 3 -	14
100 10 5 * - 2 /	25
EOF

    chmod +x /home/user/legacy_calc.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
