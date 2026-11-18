#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/webapp
mkdir -p /home/user/logs

# Create original webapp files
cat << 'EOF' > /home/user/webapp/index.py
print("Hello World")
EOF

cat << 'EOF' > /home/user/webapp/utils.py
def helper():
    pass
EOF

cat << 'EOF' > /home/user/webapp/auth.py
def login():
    return True
EOF

# Generate backup hashes based on original files
cd /home/user/webapp
sha256sum index.py utils.py auth.py > /home/user/backup_hashes.txt

# Simulate the compromise
# 1. Modify utils.py (integrity violation 1)
cat << 'EOF' > /home/user/webapp/utils.py
def helper():
    import os; os.system("whoami")
EOF

# 2. Add an untracked backdoor (integrity violation 2)
cat << 'EOF' > /home/user/webapp/shell.py
import subprocess
EOF

# 3. Create the compromised config.json
cat << 'EOF' > /home/user/webapp/config.json
{
  "app_name": "SecureApp",
  "headers": {
    "X-Frame-Options": "DENY",
    "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline' http://evil.com;"
  }
}
EOF

# Create access.log with mixed traffic
cat << 'EOF' > /home/user/logs/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /index.py HTTP/1.1" 200 2326
10.0.0.51 - - [10/Oct/2023:13:56:01 -0700] "GET /images/logo.png HTTP/1.1" 200 512
172.16.0.4 - - [10/Oct/2023:13:57:11 -0700] "GET /api/data?file=../../etc/passwd HTTP/1.1" 403 124
192.168.1.10 - - [10/Oct/2023:13:58:20 -0700] "GET /auth.py HTTP/1.1" 200 1024
203.0.113.42 - - [10/Oct/2023:13:59:00 -0700] "POST /api/upload?path=%2e%2e%2f%2e%2e%2fvar/www HTTP/1.1" 200 55
172.16.0.4 - - [10/Oct/2023:14:00:15 -0700] "GET /api/data?file=../config.json HTTP/1.1" 200 900
10.0.0.51 - - [10/Oct/2023:14:05:00 -0700] "GET /shell.py HTTP/1.1" 200 150
EOF

chmod -R 777 /home/user
