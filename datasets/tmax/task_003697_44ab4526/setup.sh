#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-server netcat-openbsd logrotate
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Setup SSH for user
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cp /home/user/.ssh/id_rsa.pub /home/user/.ssh/authorized_keys
    echo "Host 127.0.0.1\n    StrictHostKeyChecking no\n" > /home/user/.ssh/config
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/*

    # Setup directories
    mkdir -p /home/user/bin
    mkdir -p /home/user/logs

    # Create dummy logs
    dd if=/dev/zero of=/home/user/logs/db.log bs=1024 count=15
    dd if=/dev/zero of=/home/user/logs/app.log bs=1024 count=12

    # Create db-restore.sh
    cat << 'EOF' > /home/user/bin/db-restore.sh
#!/bin/bash
while true; do
  nc -l 8081 > /dev/null 2>&1
  sleep 1
done
EOF
    chmod +x /home/user/bin/db-restore.sh

    # Create app-restore.sh
    cat << 'EOF' > /home/user/bin/app-restore.sh
#!/bin/bash
while true; do
  if [ -n "$DB_PORT" ]; then
    echo "ping" | nc 127.0.0.1 $DB_PORT > /dev/null 2>&1
  fi
  sleep 2
done
EOF
    chmod +x /home/user/bin/app-restore.sh

    # Setup sshd
    mkdir -p /run/sshd
    # Allow user to login without password
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    # We need sshd to be running for the test. We can wrap the pytest command or just start it in a profile script, but since we don't control the entrypoint, we'll add a script in /etc/profile.d/ or just rely on the test framework starting it if it does. Actually, we can just start it during the environment setup or we can ensure it's started by creating a wrapper. Wait, the test framework might just run `pytest` directly. Let's add a script to start sshd if it's not running.
    echo '#!/bin/sh\nservice ssh start >/dev/null 2>&1 || true' > /etc/profile.d/start_sshd.sh
    chmod +x /etc/profile.d/start_sshd.sh
    # Also add to bashrc just in case
    echo 'sudo service ssh start >/dev/null 2>&1 || true' >> /home/user/.bashrc

    # Actually, the test framework might run `pytest` as root or user. If root, we can just start it.
    # To be safe, we will just start it in a wrapper or assume the agent will start it.
    # Wait, the prompt says "sshd must be running". I'll add a trick to start sshd when python3 is executed, but that's too hacky. Let's just ensure it's in /etc/bash.bashrc
    echo 'service ssh start >/dev/null 2>&1 || true' >> /etc/bash.bashrc

    chmod -R 777 /home/user
