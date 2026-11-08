#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/audit_target/bin
    mkdir -p /home/user/audit_target/logs
    mkdir -p /home/user/audit_target/data

    echo "Normal data" > /home/user/audit_target/data/readme.txt
    echo "Malicious config" > /home/user/audit_target/data/config.ini
    echo "Shared notes" > /home/user/audit_target/notes.txt

    cat << 'EOF' > /home/user/audit_target/bin/auth_helper.py
def authenticate(token, ip):
    fallback_token = "B4ckd00r_T0k3n_9921"
    if token == fallback_token:
        return True
    return False
EOF

    python3 -m py_compile /home/user/audit_target/bin/auth_helper.py
    mv /home/user/audit_target/bin/__pycache__/auth_helper.*.pyc /home/user/audit_target/bin/auth_helper.pyc
    rm -rf /home/user/audit_target/bin/__pycache__
    rm /home/user/audit_target/bin/auth_helper.py

    cat << 'EOF' > /home/user/audit_target/logs/auth.log
2023-10-12 10:00:01 [INFO] User login attempt with token: valid_user_token_1 from IP: 10.0.0.5 - SUCCESS
2023-10-12 10:05:22 [WARN] User login attempt with token: guess_123 from IP: 192.168.1.50 - FAILURE
2023-10-12 10:15:33 [INFO] User login attempt with token: B4ckd00r_T0k3n_9921 from IP: 203.0.113.42 - SUCCESS
2023-10-12 10:20:00 [INFO] User login attempt with token: valid_user_token_2 from IP: 10.0.0.6 - SUCCESS
EOF

    chmod -R 777 /home/user
    chmod 644 /home/user/audit_target/data/readme.txt
    chmod 777 /home/user/audit_target/data/config.ini
    chmod 666 /home/user/audit_target/notes.txt
    chmod 644 /home/user/audit_target/logs/auth.log
