#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install prerequisites
    apt-get install -y tesseract-ocr imagemagick openssh-server cron netcat-openbsd rustc cargo fonts-dejavu sudo

    # Create the user
    useradd -m -s /bin/bash user || true

    # Setup SSH keys
    mkdir -p /home/user/.ssh
    ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""
    cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys
    chmod 600 /home/user/.ssh/authorized_keys

    # Start SSH temporarily to scan keys
    service ssh start
    ssh-keyscan localhost >> /home/user/.ssh/known_hosts
    service ssh stop

    # Create telemetry data
    mkdir -p /home/user/telemetry_data
    yes "TELEMETRY_LOG_ENTRY: SYSTEM_NORMAL TIMESTAMP=1700000000 CPU=45% MEM=60% IO=10%" | head -n 150000 > /home/user/telemetry_data/syslog_01.log

    # Generate the image fixture
    mkdir -p /app
    convert -size 500x150 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
      -draw "text 20,50 'DEPLOYMENT ARCHITECTURE'" \
      -draw "text 20,90 'BACKUP_SERVER_PORT: 8443'" \
      -draw "text 20,130 'LOCAL_TUNNEL_PORT: 5050'" \
      /app/deployment_spec.png

    chown -R user:user /home/user
    chmod -R 777 /home/user
