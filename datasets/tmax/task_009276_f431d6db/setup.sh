#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user

    # 1. Create the Python source and compile it
    cat << 'EOF' > auth_handler.py
SECRET_SALT = "Inc1d3ntR3sp0ns3_S4lt!99"

def hash_log(log_content):
    import hashlib
    return hashlib.sha256((log_content + SECRET_SALT).encode('utf-8')).hexdigest()
EOF

    python3 -m py_compile auth_handler.py
    mv __pycache__/auth_handler.*.pyc auth_handler.pyc
    rm auth_handler.py
    rm -rf __pycache__

    # 2. Create the access log
    cat << 'EOF' > generate_logs.py
import hashlib

SECRET_SALT = "Inc1d3ntR3sp0ns3_S4lt!99"

logs = [
    "[2023-11-01 12:00:01] IP: 192.168.1.15 - GET /index.html",
    "[2023-11-01 12:05:22] IP: 10.0.0.42 - POST /login",
    "[2023-11-01 12:15:03] IP: 172.16.5.99 - GET /dashboard",
    "[2023-11-01 12:20:18] IP: 203.0.113.5 - POST /upload", # Tampered line
    "[2023-11-01 12:25:55] IP: 192.168.1.15 - GET /logout"
]

with open("access.log", "w") as f:
    for i, log in enumerate(logs):
        if i == 3: # Line 4 (1-indexed)
            # Tampered hash (doesn't match the actual salt)
            fake_hash = hashlib.sha256((log + "WRONGSALT").encode()).hexdigest()
            f.write(f"{log} | {fake_hash}\n")
        else:
            real_hash = hashlib.sha256((log + SECRET_SALT).encode()).hexdigest()
            f.write(f"{log} | {real_hash}\n")
EOF
    python3 generate_logs.py
    rm generate_logs.py

    # 3. Create a dummy suspicious cert
    openssl req -x509 -newkey rsa:2048 -keyout /dev/null -out cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=HackerOrg/CN=evil.local" 2>/dev/null

    chown -R user:user /home/user/*
    chmod -R 777 /home/user
