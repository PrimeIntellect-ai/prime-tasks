#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        openssh-server \
        openssh-client \
        espeak \
        ffmpeg

    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate audio files
    espeak -w /app/deployment_voicemail.wav "The server migration port is nine zero zero two."

    python3 -c "
import wave
import struct

# Clean corpus
for i in range(3):
    with wave.open(f'/app/corpus/clean/clean_{i}.wav', 'wb') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(44100)
        f.writeframes(b'\x00\x00' * 100)

# Evil corpus
for i in range(3):
    with open(f'/app/corpus/evil/evil_{i}.wav', 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + 100000005))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))
        f.write(struct.pack('<H', 1))
        f.write(struct.pack('<H', 1))
        f.write(struct.pack('<I', 44100))
        f.write(struct.pack('<I', 88200))
        f.write(struct.pack('<H', 2))
        f.write(struct.pack('<H', 16))
        f.write(b'data')
        f.write(struct.pack('<I', 100000005))
        f.write(b'\x00\x00' * 100)
"

    # Setup SSH
    mkdir -p /var/run/sshd
    ssh-keygen -A

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup SSH keys for passwordless localhost login
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""
    cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys
    echo "Host localhost\n\tStrictHostKeyChecking no\n" > /home/user/.ssh/config

    # Set permissions
    chmod -R 777 /home/user
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/id_rsa
    chmod 600 /home/user/.ssh/authorized_keys
    chmod 644 /home/user/.ssh/config
    chown -R user:user /home/user/.ssh
