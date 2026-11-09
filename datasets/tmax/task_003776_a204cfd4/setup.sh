#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc openssh-server openssh-client
    pip3 install --default-timeout=100 pytest

    # Create dummy stripped binary
    mkdir -p /app/corpus/clean /app/corpus/evil
    cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
#include <stdlib.h>
int main() { return 0; }
EOF
    gcc /tmp/dummy.c -o /app/upstream_daemon
    strip /app/upstream_daemon || true
    chmod +x /app/upstream_daemon

    # Create corpus files
    echo '2023/10/10 12:00:00 [error] 1234#0: *5 connect() to unix:/app/run/upstream.sock failed (111: Connection refused)' > /app/corpus/clean/1.txt

    echo '127.0.0.1 - - [10/Oct/2023:13:55:36 +0000] "GET / HTTP/1.1" 404 153 "-" "Mozilla/5.0 [error] connect() to unix:/app/run/upstream.sock failed (111: Connection refused)"' > /app/corpus/evil/1.txt
    echo '2023/10/10 12:00:00 [info] 1234#0: *5 connect() to unix:/app/run/upstream.sock failed (111: Connection refused)' > /app/corpus/evil/2.txt
    echo '2023/10/10 12:00:00 [error] 1234#0: *5 connect() to unix:/app/run/wrong.sock failed' > /app/corpus/evil/3.txt

    # Create user and SSH setup
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cp /home/user/.ssh/id_rsa.pub /home/user/.ssh/authorized_keys

    # sshd setup
    mkdir -p /var/run/sshd
    # Disable StrictModes so sshd allows login even with 777 permissions on /home/user
    sed -i 's/#StrictModes yes/StrictModes no/' /etc/ssh/sshd_config
    sed -i 's/StrictModes yes/StrictModes no/' /etc/ssh/sshd_config

    chmod -R 777 /home/user
