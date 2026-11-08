#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/checker.py
import base64

def check_password(pwd):
    if len(pwd) != 4:
        return False
    expected = [46, 54, 46, 20]
    for i in range(4):
        if (ord(pwd[i]) ^ 0x42) + i != expected[i]:
            return False
    return True

def get_token(pwd):
    if not check_password(pwd):
        return "Access Denied"
    payload = "cRcRHgdfR1AWDwMNAA0SBRYfBA0dBAEABRccBhc="
    enc = base64.b64decode(payload).decode('latin1')
    res = ""
    for i in range(len(enc)):
        res += chr(ord(enc[i]) ^ ord(pwd[i % 4]))
    return res
EOF

    python3 -m py_compile /home/user/checker.py
    mv /home/user/__pycache__/checker.*.pyc /home/user/checker.pyc
    rm -rf /home/user/__pycache__
    rm /home/user/checker.py

    chmod -R 777 /home/user
