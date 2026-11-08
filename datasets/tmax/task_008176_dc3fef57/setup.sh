#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /home/user/suspicious_repo/lib
cd /home/user/suspicious_repo

# 1. Environment Misconfiguration (Shadowing)
cat << 'EOF' > lib/hashlib.py
raise ImportError("FATAL: Environment corrupted by attacker.")
EOF

# 2. Infinite Recursion in vm.py
cat << 'EOF' > vm.py
def evaluate(node):
    if isinstance(node, str):
        return node
    elif isinstance(node, list):
        # BUG: recursively calls evaluate(node) instead of evaluate(item)
        return "".join([evaluate(node) for item in node])
    else:
        return ""
EOF

# 3. Analyze script
cat << 'EOF' > analyze.py
import sys
import os

# Attacker forces local lib directory to shadow standard library
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))
import hashlib # Will fail until lib/hashlib.py is removed
import vm

if len(sys.argv) < 2:
    print("Usage: python3 analyze.py <key>")
    sys.exit(1)

key = sys.argv[1]

with open(os.path.join(os.path.dirname(__file__), 'payload.dat'), 'r') as f:
    data = f.read()

# XOR Decryption
decrypted = "".join(chr(ord(c) ^ ord(key[i % len(key)])) for i, c in enumerate(data))

try:
    ast_tree = eval(decrypted)
    result = vm.evaluate(ast_tree)
    with open('/home/user/flag.txt', 'w') as f:
        f.write(result)
    print("Successfully wrote to /home/user/flag.txt")
except Exception as e:
    print(f"Failed to evaluate: {e}")
    sys.exit(1)
EOF

# 4. Generate the payload
python3 -c '
key = "v01d_w4lk3r_77"
ast_repr = "[\"F\", \"L\", \"A\", \"G\", \"{\", [\"r\", \"3\", \"v\", \"3\", \"r\", \"s\", \"3\"], \"_\", \"3\", \"n\", \"g\", \"1\", \"n\", \"3\", \"3\", \"r\", \"}\"]"
encrypted = "".join(chr(ord(c) ^ ord(key[i % len(key)])) for i, c in enumerate(ast_repr))
with open("payload.dat", "w") as f:
    f.write(encrypted)
'

# 5. Git repository setup
git init
git config user.name "Attacker"
git config user.email "attacker@example.com"

# Commit 1: Add the secret key
echo "v01d_w4lk3r_77" > secret_key.txt
git add secret_key.txt
git commit -m "Initialize project and store key"

# Commit 2: Remove the secret key and add the rest
git rm secret_key.txt
git add lib/hashlib.py vm.py analyze.py payload.dat
git commit -m "Remove key, add encrypted payload and tools"

# Create user and fix permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
