#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl ffmpeg espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the voicemail audio file
    espeak -w /app/voicemail.wav "yellow submarine forty two"

    # Create the plain text log file
    cat << 'EOF' > /app/web_traffic.log
192.168.1.100 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326
192.168.1.105 - - [10/Oct/2023:13:55:40 -0700] "GET /images/../../../../etc/passwd HTTP/1.1" 404 209
10.0.5.55 - - [10/Oct/2023:13:56:01 -0700] "GET /search?q=%3Cscript%3Ealert(1)%3C/script%3E HTTP/1.1" 200 1024
172.16.8.99 - - [10/Oct/2023:13:57:11 -0700] "GET /login?redirect=%2E%2E%2F%2E%2E%2Fetc%2Fshadow HTTP/1.1" 403 512
10.1.1.1 - - [10/Oct/2023:13:58:00 -0700] "GET /about.html HTTP/1.1" 200 1024
192.168.1.200 - - [10/Oct/2023:13:59:00 -0700] "POST /api/data HTTP/1.1" 201 50
EOF

    # Encrypt the log file with the passphrase
    openssl enc -aes-256-cbc -pbkdf2 -in /app/web_traffic.log -out /app/web_traffic.log.enc -pass pass:"yellow submarine forty two"

    # Remove the plain text log
    rm /app/web_traffic.log

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
