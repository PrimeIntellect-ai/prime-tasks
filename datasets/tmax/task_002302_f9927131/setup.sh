#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    # 1. Generate the image
    convert -size 400x100 xc:black -font DejaVu-Sans-Mono -pointsize 20 -fill white -draw "text 10,50 'Old Master: MasterSecr3t!'" /app/screenshot.png

    # 2. Create auth_service.py
    cat << 'EOF' > /app/auth_service.py
import hashlib
def generate_hash(old_password, new_password):
    # Weak legacy key derivation
    combined = "old_pwd_" + old_password + "_" + new_password
    return hashlib.sha256(combined.encode()).hexdigest()
EOF

    # 3. Compile to .pyc and remove the original .py file
    python3 -m py_compile /app/auth_service.py
    mv /app/__pycache__/auth_service.*.pyc /app/auth_service.pyc
    rm /app/auth_service.py
    rm -rf /app/__pycache__ || true

    # 4. Create the hidden test log
    cat << 'EOF' > /app/hidden_test.log
10.0.0.5 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=http://evil.com HTTP/1.1" 302 154 "-" "Mozilla/5.0"
192.168.1.100 - - [10/Oct/2023:13:56:00 -0700] "GET /login?return_to=//malicious.org HTTP/1.1" 302 154 "-" "curl/7.68.0"
172.16.0.4 - - [10/Oct/2023:13:57:12 -0700] "GET /login?redirect=https://badsite.net/login HTTP/1.1" 302 154 "-" "Mozilla/5.0"
10.0.0.2 - - [10/Oct/2023:13:58:00 -0700] "GET /login?next=/dashboard HTTP/1.1" 302 154 "-" "Mozilla/5.0"
192.168.1.50 - - [10/Oct/2023:13:59:00 -0700] "GET /login?next=dashboard HTTP/1.1" 200 154 "-" "Mozilla/5.0"
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
