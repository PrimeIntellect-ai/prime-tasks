#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx curl
    pip3 install pytest flask

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/legacy_emulator.py
def evaluate(program):
    stack = []
    tokens = program.split()
    for token in tokens:
        if token == 'ADD':
            a = stack.pop()
            b = stack.pop()
            stack.append(a + b)
        elif token == 'MUL':
            a = stack.pop()
            b = stack.pop()
            stack.append(a * b)
        else:
            stack.append(int(token))
    return stack.pop()

if __name__ == '__main__':
    print evaluate("2 3 ADD")
EOF

    chmod -R 777 /home/user
