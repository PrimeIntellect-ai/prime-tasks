#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/vars.json
{
    "loc": 5000,
    "cov": 80,
    "cyclomatic": 250,
    "bonus": 150
}
EOF

echo -n "bG9jIGNvdiAqIDEwMCAvIGN5Y2xvbWF0aWMgLSBib251cyAr" > /home/user/pipeline_data.b64

cat << 'EOF' > /home/user/legacy_eval.py
import json
import base64

def evaluate():
    with open('/home/user/pipeline_data.b64', 'r') as f:
        encoded_expr = f.read().strip()

    expr = base64.b64decode(encoded_expr).decode('utf-8')

    with open('/home/user/vars.json', 'r') as f:
        variables = json.load(f)

    stack = []
    tokens = expr.split()

    for token in tokens:
        if token in ['+', '-', '*', '/']:
            b = stack.pop()
            a = stack.pop()
            if token == '+':
                stack.append(a + b)
            elif token == '-':
                stack.append(a - b)
            elif token == '*':
                stack.append(a * b)
            elif token == '/':
                stack.append(a // b)
        else:
            if token in variables:
                stack.append(variables[token])
            else:
                stack.append(int(token))

    with open('/home/user/result.txt', 'w') as f:
        f.write(str(stack[0]))

if __name__ == '__main__':
    evaluate()
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
