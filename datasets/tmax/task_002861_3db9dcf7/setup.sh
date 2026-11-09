#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak pocketsphinx
    pip3 install pytest SpeechRecognition

    mkdir -p /app

    cat << 'EOF' > /app/oracle_eval.py
import sys
import math

def evaluate(expr):
    tokens = expr.split()
    stack = []
    min_bound = -9999
    max_bound = 9999

    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token == 'MIN':
            i += 1
            if i >= len(tokens): return "ERROR"
            try: min_bound = int(tokens[i])
            except ValueError: return "ERROR"
        elif token == 'MAX':
            i += 1
            if i >= len(tokens): return "ERROR"
            try: max_bound = int(tokens[i])
            except ValueError: return "ERROR"
        elif token in ('+', '-', '*', '/'):
            if len(stack) < 2: return "ERROR"
            b = stack.pop()
            a = stack.pop()
            if token == '+': stack.append(a + b)
            elif token == '-': stack.append(a - b)
            elif token == '*': stack.append(a * b)
            elif token == '/':
                if b == 0: return "ERROR"
                stack.append(int(a / b))
        else:
            try: stack.append(int(token))
            except ValueError: return "ERROR"
        i += 1

    if len(stack) != 1: return "ERROR"

    res = stack[0]
    if res > max_bound: res = max_bound
    if res < min_bound: res = min_bound
    return str(res)

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("ERROR")
    else:
        print(evaluate(sys.argv[1]))
EOF

    cat << 'EOF' > /tmp/memo.txt
We need a custom Reverse Polish Notation evaluator. It should support integer numbers and the operators plus, minus, star, and slash. Slash is integer division. We also have constraint modifiers: MAX followed by a number, and MIN followed by a number. These modifiers don't go on the stack; instead, they update the global bounds for the final result. The default maximum bound is 9999, and the default minimum bound is minus 9999. If multiple MINs or MAXes are specified, the latest one overrides the previous ones. After evaluating all operations, the final remaining value on the stack must be clamped to these bounds. Remember to output ERROR for any invalid states.
EOF

    espeak -w /app/memo.wav -f /tmp/memo.txt
    rm /tmp/memo.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
