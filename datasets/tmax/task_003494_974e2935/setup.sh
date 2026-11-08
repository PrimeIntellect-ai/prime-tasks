#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg gawk
    pip3 install pytest

    mkdir -p /app/logs

    # Generate the voicemail audio file
    espeak -w /app/voicemail.wav "We have a breach. The anomaly started on October twelfth at exactly twenty three fourteen. Please check the logs."

    # Create auth.log
    cat << 'EOF' > /app/logs/auth.log
Oct 12 23:13:55 server sshd[10101]: Accepted publickey for user from 10.0.0.5 port 1111 ssh2
Oct 12 23:14:12 server sshd[10102]: Failed password for invalid user root from 203.0.113.42 port 33333 ssh2
Oct 12 23:14:15 server sshd[10102]: Connection closed by invalid user root 203.0.113.42 port 33333 [preauth]
EOF

    # Create access.log
    cat << 'EOF' > /app/logs/access.log
203.0.113.42 - - [12/Oct/2023:23:15:01 +0000] "GET /phpmyadmin HTTP/1.1" 404 134 "-" "curl/7.68.0"
203.0.113.42 - - [12/Oct/2023:23:15:05 +0000] "POST /login HTTP/1.1" 200 512 "-" "curl/7.68.0"
EOF

    # Create syslog
    cat << 'EOF' > /app/logs/syslog
Oct 12 23:15:10 server kernel: [ 1234.5678] Firewall block: IN=eth0 OUT= MAC=... SRC=203.0.113.42 DST=...
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
