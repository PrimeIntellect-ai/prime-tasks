#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/webapp
    mkdir -p /home/user/.ssh

    # Create SSH key with bad permissions
    echo "PRIVATE KEY DATA" > /home/user/.ssh/id_rsa
    chmod 777 /home/user/.ssh/id_rsa

    # Create webapp files
    cat << 'EOF' > /home/user/webapp/utils.py
def helper():
    pass
EOF

    cat << 'EOF' > /home/user/webapp/views.py
def get_user_page(user_id, name):
    html = "<div>"
    html += "<h1>User Profile</h1>"
    html += "<p>Name: " + name + "</p>"
    html += "</div>"
    return html
EOF

    # Safe version of server.py
    cat << 'EOF' > /home/user/webapp/server.py
import os

def ping_host(host):
    # safe implementation
    return "PONG"
EOF

    # Generate checksums
    cd /home/user/webapp
    sha256sum *.py > checksums.txt

    # Overwrite server.py with vulnerable version (line 4 has injection)
    cat << 'EOF' > /home/user/webapp/server.py
import os

def ping_host(host):
    return os.popen("ping -c 1 " + host).read()
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
