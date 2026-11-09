#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git strace
pip3 install pytest

mkdir -p /home/user/math_tool
cd /home/user/math_tool

git config --global init.defaultBranch main
git config --global user.email "user@example.com"
git config --global user.name "User"
git init

# Commit 1: Working code with API Key
cat << 'EOF' > compute.py
import sys

API_KEY = "SK-9942-ABCF-1111"

def compute_math():
    a, b = 0, 1
    for _ in range(5000):
        a, b = b, (a + b) % 100000
    return a

if __name__ == "__main__":
    result = compute_math()
    with open("/home/user/result.txt", "w") as f:
        f.write(str(result))
EOF
git add compute.py
git commit -m "Initial commit: working math tool"

# Commit 2: Buggy code, removed API Key, obfuscated permission error path
cat << 'EOF' > compute.py
import sys
import os
import base64

API_KEY = os.environ.get("API_KEY", "")

# Deep recursion without memoization to cause RecursionError
def compute_math(n):
    if n == 0: return 0
    if n == 1: return 1
    return (compute_math(n-1) + compute_math(n-2)) % 100000

if __name__ == "__main__":
    sys.setrecursionlimit(500)
    try:
        result = compute_math(5000)
    except Exception as e:
        # Intentionally crash to simulate core dump/traceback
        raise RuntimeError("Math computation failed") from e

    # Obfuscated path: /opt/restricted_math_out.txt
    bad_path = base64.b64decode(b'L29wdC9yZXN0cmljdGVkX21hdGhfb3V0LnR4dA==').decode('utf-8')
    try:
        with open(bad_path, "w") as f:
            f.write(str(result))
    except PermissionError:
        os.abort() # Cause a core dump if permission denied
EOF
git add compute.py
git commit -m "Refactor math logic to be recursive and secure API key"

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/math_tool
chmod -R 777 /home/user
