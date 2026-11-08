#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest flask fastapi uvicorn requests

    # Create app directory
    mkdir -p /app

    # Create system_auth.log
    cat << 'EOF' > /app/system_auth.log
Jan 12 08:34:11 server sshd[123]: Failed password for root from 192.168.1.5
Jan 12 08:45:00 server su[456]: Successful su for root by user
Jan 12 09:12:05 server backdoor[789]: Backdoor planted. Hash: 2fa8d575fa8b30b42d765b2d718ec0db92ff1df2ed7a34731a5ec409f3e4eaf9
EOF

    # Create nginx_access.log
    cat << 'EOF' > /app/nginx_access.log
192.168.1.10 - - [12/Jan/2024:10:00:00 +0000] "GET /index.html HTTP/1.1" 200 1024
10.99.5.42 - - [12/Jan/2024:10:05:12 +0000] "GET /download?file=../../../../etc/passwd HTTP/1.1" 403 154
10.99.5.42 - - [12/Jan/2024:10:06:01 +0000] "GET /download?file=../../../../etc/shadow HTTP/1.1" 200 892
172.16.0.5 - - [12/Jan/2024:10:10:11 +0000] "GET /download?file=normal.txt HTTP/1.1" 200 400
EOF

    # Generate the intercepted call audio file
    espeak -w /app/intercepted_call.wav "The password is the word admin followed by a three digit number."

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
