#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq socat netcat-openbsd gawk wget unzip
    pip3 install pytest

    # Create user and home directory
    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Download and vendor bashttpd
    cd /app
    wget -q https://github.com/avleen/bashttpd/archive/refs/heads/master.zip
    unzip -q master.zip
    rm master.zip

    # Apply perturbation: change URI parsing to extract $3 instead of the path
    sed -i 's/REQUEST_URI=.*/REQUEST_URI=$(echo "$REQUEST_LINE" | awk '"'"'{print $3}'"'"')/' /app/bashttpd-master/bashttpd

    # Create access log file
    cat << 'EOF' > /home/user/access.log
[2023-10-01 10:00:05] 192.168.1.1 "GET /index.html HTTP/1.1" 200 120
[2023-10-01 10:00:15] 192.168.1.2 "GET /api HTTP/1.1" 500 200
[2023-10-01 10:00:15] 192.168.1.2 "GET /api HTTP/1.1" 500 200
[2023-10-01 10:01:10] 192.168.1.3 "POST /login HTTP/1.1" 401 50
EOF

    # Fix permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
