#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import base64
import zlib

os.makedirs("/home/user/app/uploads", exist_ok=True)

code = """
import sys, os, base64

def d(x, k): 
    return ''.join(chr(ord(c)^k) for c in x)

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    # The handler expects base64 encoded strings that, when decoded, are XOR'd with 42
    f = d(base64.b64decode(sys.argv[1]).decode('utf-8'), 42)
    c = d(base64.b64decode(sys.argv[2]).decode('utf-8'), 42)

    upload_dir = "/home/user/app/uploads"
    p = os.path.join(upload_dir, f)

    with open(p, 'w') as out: 
        out.write(c)

if __name__=='__main__': 
    main()
"""

obf = base64.b64encode(zlib.compress(code.encode('utf-8'))).decode('utf-8')

with open('/home/user/app/handler.py', 'w') as f:
    f.write(f"import base64,zlib,sys;exec(zlib.decompress(base64.b64decode('{obf}')).decode('utf-8'))")

os.chmod('/home/user/app/handler.py', 0o755)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
