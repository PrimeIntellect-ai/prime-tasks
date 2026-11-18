#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl openssh-server openssh-client sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/dashboard_data
    echo "active_dashboards 42" > /home/user/dashboard_data/metrics_source.txt

    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/id_rsa

    mkdir -p /run/sshd
    echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config

    # Ensure sshd starts when bash is invoked
    echo 'if ! pgrep -f "/usr/sbin/sshd" > /dev/null; then sudo /usr/sbin/sshd; fi' >> /etc/bash.bashrc
    echo "user ALL=(ALL) NOPASSWD: /usr/sbin/sshd" >> /etc/sudoers

    chown -R user:user /home/user
    chmod -R 777 /home/user
