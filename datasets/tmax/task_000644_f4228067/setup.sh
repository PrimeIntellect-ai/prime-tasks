#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/math_api

cat << 'EOF' > /home/user/math_api/decoder.py
def decode_query(hex_str: str) -> str:
    # BUG: XORs the hex characters instead of bytes, bad decode
    res = ""
    for char in hex_str:
        res += chr(ord(char) ^ 0x42)
    return res
EOF

cat << 'EOF' > /home/user/math_api/parser.py
def parse_query(query_str: str):
    # State machine to parse "P c0 c1 c2 | G guess"
    state = "START"
    coeffs = []
    guess = 0.0
    current_token = ""

    for char in query_str + " ":
        if state == "START":
            if char == 'P':
                state = "COEFFS"
        elif state == "COEFFS":
            if char == ' ':
                if current_token:
                    # BUG: removes negative signs
                    coeffs.append(float(current_token.replace("-", "")))
                    current_token = ""
            elif char == '|':
                state = "WAIT_GUESS"
                current_token = ""
            else:
                current_token += char
        elif state == "WAIT_GUESS":
            if char == 'G':
                state = "GUESS"
        elif state == "GUESS":
            if char == ' ' and not current_token:
                continue
            elif char == ' ':
                guess = float(current_token)
                current_token = ""
            else:
                current_token += char

    return coeffs, guess
EOF

cat << 'EOF' > /home/user/math_api/solver.py
def evaluate_poly(coeffs, x):
    res = 0.0
    for i, c in enumerate(coeffs):
        res += c * (x ** i)
    return res

def evaluate_derivative(coeffs, x):
    res = 0.0
    # BUG: Derivative logic is wrong (i * x**(i) instead of i * x**(i-1))
    for i in range(1, len(coeffs)):
        res += coeffs[i] * i * (x ** i)
    return res

def newton_root(coeffs, guess):
    x = guess
    for _ in range(100):
        fx = evaluate_poly(coeffs, x)
        if abs(fx) < 1e-7:
            return x
        dfx = evaluate_derivative(coeffs, x)
        if dfx == 0:
            break
        x = x - (fx / dfx)
    return x
EOF

cat << 'EOF' > /home/user/math_api/main.py
import sys
from decoder import decode_query
from parser import parse_query
from solver import newton_root

def run(hex_str):
    query_str = decode_query(hex_str)
    coeffs, guess = parse_query(query_str)
    root = newton_root(coeffs, guess)
    return root

if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(run(sys.argv[1]))
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
