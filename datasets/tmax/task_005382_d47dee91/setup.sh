#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 python3-pip \
        nginx redis-server openssh-server systemd systemd-sysv \
        curl wget sudo bash cargo rustc dbus dbus-user-session

    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup legacy filter
    mkdir -p /app
    cat << 'EOF' > /app/legacy_filter.sh
#!/bin/bash
# Legacy oracle script
sed -e 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/TIMESTAMP/g' -e 's/ERROR/CRITICAL/g'
EOF
    chmod +x /app/legacy_filter.sh

    # Setup systemd user service
    mkdir -p /home/user/.config/systemd/user
    cat << 'EOF' > /home/user/.config/systemd/user/log-filter.service
[Unit]
Description=Log Filter Service

[Service]
ExecStart=/app/legacy_filter.sh
StandardInput=null
EOF

    # Setup SSH
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -N "" -f /home/user/.ssh/id_rsa
    cp /home/user/.ssh/id_rsa.pub /home/user/.ssh/authorized_keys
    chown -R user:user /home/user/.ssh
    chmod 700 /home/user/.ssh
    chmod 600 /home/user/.ssh/*

    # Enable services
    systemctl enable redis-server
    systemctl enable nginx
    systemctl enable ssh

    chmod -R 777 /home/user
