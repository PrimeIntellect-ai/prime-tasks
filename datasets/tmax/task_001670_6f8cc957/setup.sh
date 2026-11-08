#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    mkdir -p /home/user/suspicious_tool
    cd /home/user/suspicious_tool
    git init

    cat << 'EOF' > malware.py
import hashlib
import os

# Author note: NEVER leak this!
SECRET_TOKEN = "C2_TOK_77f9a2b4_exfiltrate"

def check_c2_auth(token):
    expected_hash = "6d2b512ed7e3e7f43db48e23fc7b4a2eb7cececc6931551061f0084f5cfb591d" # SHA256 of C2_TOK_77f9a2b4_exfiltrate
    return hashlib.sha256(token.encode()).hexdigest() == expected_hash

def run_payload():
    pass
EOF

    cat << 'EOF' > requirements.txt
requests==2.28.2
urllib3==1.26.15
EOF

    git config user.email "hacker@evil.com"
    git config user.name "Hacker"
    git add malware.py requirements.txt
    git commit -m "Initial commit of payload runner"

    cat << 'EOF' > malware.py
import hashlib
import os

def check_c2_auth(token):
    expected_hash = "6d2b512ed7e3e7f43db48e23fc7b4a2eb7cececc6931551061f0084f5cfb591d"
    return hashlib.sha256(token.encode()).hexdigest() == expected_hash

def run_payload():
    pass
EOF

    git add malware.py
    git commit -m "OpSec: read token dynamically, remove hardcoded secret"

    cat << 'EOF' > requirements.txt
PyJWT==2.8.0
cryptography==3.3.1
EOF

    git add requirements.txt
    git commit -m "Add JWT and crypto libs for new payload"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
