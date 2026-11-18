#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git python-is-python3
pip3 install pytest

mkdir -p /home/user/poly_parser
cd /home/user/poly_parser
git init
git config --global user.email "test@example.com"
git config --global user.name "Test User"

# Commit 1 (v1.0): Working evaluate.py
cat << 'EOF' > evaluate.py
import re
import sys
import argparse

def parse_coefficient(line):
    # Parses strings like COEFF(-1.23e-4)
    match = re.search(r'COEFF\(([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\)', line)
    if not match:
        raise ValueError(f"Could not parse coefficient from: {line}")
    return float(match.group(1))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", required=True)
    args = parser.parse_args()

    with open(args.test, 'r') as f:
        for line in f:
            val = parse_coefficient(line.strip())
            print(f"Parsed: {val}")
EOF
git add evaluate.py
git commit -m "Initial commit of evaluate.py"
git tag v1.0

# Commit 2: Accidentally add .env with secret
cat << 'EOF' > .env
DIAGNOSTIC_TOKEN=f9b23c4a-8d1e-4567-b90a-123456abcdef
EOF
git add .env
git commit -m "Add environment configuration"

# Commit 3: Remove .env
git rm .env
git commit -m "Remove accidentally committed .env file"

# Commit 4: The regression
cat << 'EOF' > evaluate.py
import re
import sys
import argparse

def parse_coefficient(line):
    # Parses strings like COEFF(-1.23)
    match = re.search(r'COEFF\(([-+]?\d*\.?\d+)\)', line)
    if not match:
        raise ValueError(f"Could not parse coefficient from: {line}")
    return float(match.group(1))

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", required=True)
    args = parser.parse_args()

    with open(args.test, 'r') as f:
        for line in f:
            val = parse_coefficient(line.strip())
            print(f"Parsed: {val}")
EOF
git add evaluate.py
git commit -m "Optimize regex for faster parsing"
BAD_COMMIT=$(git rev-parse HEAD)
echo $BAD_COMMIT > /tmp/bad_commit_hash.txt

# Commit 5: Add edge case test file and diagnostic server
cat << 'EOF' > edge_case.txt
COEFF(1.5e-4)
EOF
cat << 'EOF' > diagnostic_server.py
import argparse
import time
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Diagnostic server running")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--token", required=True)
    args = parser.parse_args()
    if args.token != "f9b23c4a-8d1e-4567-b90a-123456abcdef":
        print("Invalid token!")
        exit(1)

    with socketserver.TCPServer(("", 8080), Handler) as httpd:
        print("serving at port", 8080)
        httpd.serve_forever()
EOF
git add edge_case.txt diagnostic_server.py
git commit -m "Add edge case test and diagnostic server"

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/poly_parser
chmod -R 777 /home/user
