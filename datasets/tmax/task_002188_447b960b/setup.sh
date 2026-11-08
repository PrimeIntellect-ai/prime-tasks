#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate a test Ed25519 key
    ssh-keygen -t ed25519 -f /home/user/.target_key -N "" -q

    # Base64 encode the key (no wrapping)
    KEY_B64=$(cat /home/user/.target_key | base64 -w 0)
    PORT=13337

    # Add to bashrc so it runs when the agent or tests start a shell
    echo "if ! pgrep -f dummy_service > /dev/null; then" >> /home/user/.bashrc
    echo "  python3 -c \"import time; time.sleep(100000)\" dummy_service --secret-key=$KEY_B64 --exfil-port=$PORT &" >> /home/user/.bashrc
    echo "fi" >> /home/user/.bashrc

    echo "if ! pgrep -f dummy_service > /dev/null; then" >> /etc/bash.bashrc
    echo "  python3 -c \"import time; time.sleep(100000)\" dummy_service --secret-key=$KEY_B64 --exfil-port=$PORT &" >> /etc/bash.bashrc
    echo "fi" >> /etc/bash.bashrc

    chmod -R 777 /home/user
