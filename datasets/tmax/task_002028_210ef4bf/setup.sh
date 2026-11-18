#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo openssl espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/evidence

    # Generate the audio file
    espeak -w /app/evidence/voicemail.wav "The encryption password is the word 'panther' followed by a four digit pin."

    # Generate the payload
    cat << 'EOF' > /tmp/plain.json
[
  {"id": 1, "username": "admin", "ssn": "000-11-2222", "private_ssh_key": "-----BEGIN OPENSSH PRIVATE KEY-----\n..."},
  {"id": 2, "username": "dev", "ssn": "999-88-7777", "private_ssh_key": "-----BEGIN RSA PRIVATE KEY-----\n..."}
]
EOF

    # Encrypt the payload
    openssl enc -aes-256-cbc -pbkdf2 -salt -in /tmp/plain.json -out /app/evidence/payload.enc -pass pass:panther4829
    rm /tmp/plain.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
