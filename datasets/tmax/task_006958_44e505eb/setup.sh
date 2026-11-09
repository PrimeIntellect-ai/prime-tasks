#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary tools for the task
    apt-get install -y cargo rustc openssh-client gawk

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create incident directory and files
    mkdir -p /home/user/incident

    # Generate SSH keys and fingerprints
    ssh-keygen -t ed25519 -f /home/user/incident/good_key -N "" -q
    ssh-keygen -t ed25519 -f /home/user/incident/bad_key -N "" -q

    GOOD_FP=$(ssh-keygen -l -f /home/user/incident/good_key.pub | awk '{print $2}')
    BAD_FP=$(ssh-keygen -l -f /home/user/incident/bad_key.pub | awk '{print $2}')

    # Create server.log
    cat <<EOF > /home/user/incident/server.log
[2023-10-01 12:00:01] SSH_LOGIN: IP=192.168.1.50 FINGERPRINT=${GOOD_FP}
[2023-10-01 12:05:00] APP_REQ: IP=192.168.1.50 PAYLOAD=68656c6c6f20776f726c64
[2023-10-01 13:00:00] SSH_LOGIN: IP=10.0.0.99 FINGERPRINT=${BAD_FP}
[2023-10-01 13:01:00] APP_REQ: IP=10.0.0.99 PAYLOAD=7767657420687474703a2f2f6576696c2e636f6d2f7368656c6c2e73683b2062617368207368656c6c2e7368
[2023-10-01 13:05:00] APP_REQ: IP=192.168.1.50 PAYLOAD=73746174757320636865636b
EOF

    # Create authorized_keys
    cat /home/user/incident/good_key.pub > /home/user/incident/authorized_keys
    cat /home/user/incident/bad_key.pub >> /home/user/incident/authorized_keys

    # Clean up temporary key files
    rm /home/user/incident/good_key /home/user/incident/good_key.pub /home/user/incident/bad_key /home/user/incident/bad_key.pub

    # Set permissions
    chmod -R 777 /home/user
