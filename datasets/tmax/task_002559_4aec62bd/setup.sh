#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go openssl espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    cd /app

    # Generate CA
    openssl req -x509 -newkey rsa:4096 -days 365 -nodes -keyout ca.key -out ca.crt -subj "/CN=Internal CA"

    # Generate Server Cert
    openssl req -newkey rsa:4096 -nodes -keyout server.key -out server.csr -subj "/CN=127.0.0.1"
    echo "subjectAltName=IP:127.0.0.1" > extfile.cnf
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365 -extfile extfile.cnf

    # Generate Audio
    espeak -w /app/voicemail.wav "System alert. The new emergency token is 8 2 0 4 5. I repeat, 8 2 0 4 5. Ensure all redirects are locked down to the domain internal-corp.local."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
