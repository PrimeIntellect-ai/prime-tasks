#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/mathvm.py
import sys

def evaluate(program):
    stack = []
    for line in program.strip().split('\n'):
        parts = line.split()
        if not parts: continue
        op = parts[0]
        if op == 'PUSH':
            stack.append(int(parts[1]))
        elif op == 'ADD':
            a = stack.pop()
            b = stack.pop()
            stack.append(b + a)
        elif op == 'SUB':
            a = stack.pop()
            b = stack.pop()
            stack.append(b - a)
        elif op == 'MUL':
            a = stack.pop()
            b = stack.pop()
            stack.append(b * a)
        elif op == 'DIV':
            a = stack.pop()
            b = stack.pop()
            stack.append(b // a)
    return stack[-1] if stack else 0

if __name__ == "__main__":
    with open(sys.argv[1], 'r') as f:
        print(evaluate(f.read()))
EOF

    cat << 'EOF' > /home/user/test_program.txt
PUSH 10
PUSH 20
ADD
PUSH 5
MUL
PUSH 3
SUB
PUSH 2
DIV
PUSH 100
ADD
PUSH 25
SUB
EOF

    chmod -R 777 /home/user
