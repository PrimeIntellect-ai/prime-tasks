#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incident_data

    cat << 'EOF' > /home/user/incident_data/sshd_config
# This is the sshd server system-wide configuration file.
Port 22
#ListenAddress 0.0.0.0

# Authentication:
LoginGraceTime 2m
PermitRootLogin yes
StrictModes yes
MaxAuthTries 6

PubkeyAuthentication yes

# To disable tunneled clear text passwords, change to no here!
PasswordAuthentication yes
PermitEmptyPasswords no

X11Forwarding yes
PrintMotd no
EOF

    cat << 'EOF' > /home/user/incident_data/server_logs.txt
[2023-10-24 10:00:01] [INFO] sshd service started
[2023-10-24 10:02:15] [WARN] Invalid configuration detected
[2023-10-24 10:05:22] [ERROR] Debug dump of application crash:
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD8Y+Z... fake key data ...
m9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZWQyNTUxOQAAACD8Y+Z
-----END OPENSSH PRIVATE KEY-----
[2023-10-24 10:05:23] [INFO] Connection closed from 192.168.1.50
[2023-10-24 10:10:00] [INFO] System shutdown initiated
EOF

    chmod -R 777 /home/user
