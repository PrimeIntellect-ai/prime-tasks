#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server espeak-ng
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true
    useradd -m -s /bin/bash auditor || true

    # Create audio file
    mkdir -p /app
    espeak-ng -w /app/voicemail.wav "Hey, it's Dave. I temporarily set the server passphrase to hunter2_secure_199."

    # Setup SSH keys
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N "hunter2_secure_199"

    mkdir -p /home/auditor/.ssh
    cp /home/user/.ssh/id_rsa.pub /home/auditor/.ssh/authorized_keys
    chown -R auditor:auditor /home/auditor/.ssh
    chmod 700 /home/auditor/.ssh
    chmod 600 /home/auditor/.ssh/authorized_keys

    # Setup SSH server
    mkdir -p /run/sshd
    echo "Port 2222" >> /etc/ssh/sshd_config

    # Auto-start sshd when container runs commands
    echo '#!/bin/sh' > /.singularity.d/env/99-sshd.sh
    echo '/usr/sbin/sshd -p 2222 2>/dev/null || true' >> /.singularity.d/env/99-sshd.sh
    chmod +x /.singularity.d/env/99-sshd.sh

    # Create proc audits
    mkdir -p /var/log/proc_audits/
    echo "cmdline: myprocess" > /var/log/proc_audits/1.txt

    # Create evaluation corpora
    mkdir -p /var/opt/eval/evil/
    mkdir -p /var/opt/eval/clean/

    echo "cmdline: --password=Secret" > /var/opt/eval/evil/1.txt
    echo "cmdline: normal daemon" > /var/opt/eval/clean/1.txt

    chmod -R 777 /home/user
