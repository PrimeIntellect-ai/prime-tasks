#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server openssh-client espeak ffmpeg
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup SSH
    mkdir -p /run/sshd
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cat /home/user/.ssh/id_rsa.pub > /home/user/.ssh/authorized_keys

    cat << 'EOF' > /home/user/.ssh/config
Host *
    PubkeyAuthentication no
EOF

    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/id_rsa /home/user/.ssh/id_rsa.pub /home/user/.ssh/authorized_keys /home/user/.ssh/config
    chown -R user:user /home/user/.ssh

    # Generate audio file
    mkdir -p /app
    espeak -w /app/capacity_request.wav "Please analyze the caching-service logs"

    # Generate logs
    mkdir -p /var/log/services/caching-service
    python3 -c '
import os
import random
os.makedirs("/var/log/services/caching-service", exist_ok=True)
with open("/var/log/services/caching-service/usage.log.1", "w") as f:
    for i in range(1, 100):
        # y = 0.4112 * x + 44.59 => at x=100, y=85.71
        cpu = 0.4112 * i + 44.59
        mem = 30.0 + random.random()
        f.write(f"{i} {cpu:.2f} {mem:.2f}\n")
'

    chmod -R 777 /home/user
