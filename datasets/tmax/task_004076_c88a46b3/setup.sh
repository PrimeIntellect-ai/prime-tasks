#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/.ssh
    mkdir -p /home/user/evidence

    # Create valid keys
    ssh-keygen -t ed25519 -f /home/user/evidence/valid1 -q -N "" -C "admin@internal"
    ssh-keygen -t rsa -b 2048 -f /home/user/evidence/valid2 -q -N "" -C "backup@internal"

    # Create rogue key
    ssh-keygen -t ed25519 -f /home/user/evidence/rogue -q -N "" -C "hacker@pwned"

    # Assemble authorized_keys
    cat /home/user/evidence/valid1.pub > /home/user/.ssh/authorized_keys
    cat /home/user/evidence/rogue.pub >> /home/user/.ssh/authorized_keys
    cat /home/user/evidence/valid2.pub >> /home/user/.ssh/authorized_keys

    # Create valid_keys.pub (only contains the good ones)
    cat /home/user/evidence/valid1.pub > /home/user/evidence/valid_keys.pub
    cat /home/user/evidence/valid2.pub >> /home/user/evidence/valid_keys.pub

    # Create encoded payload
    echo -n "https://trusted.com/api,http://internal.net/sync,http://evil-c2.xyz/exfil,https://update.server.com/bin" | base64 > /home/user/evidence/payload.b64

    chown -R user:user /home/user/.ssh /home/user/evidence

    chmod -R 777 /home/user
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/authorized_keys
