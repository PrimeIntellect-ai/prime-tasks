#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core gcc build-essential
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpus/evil /app/corpus/clean

    # Create backup.conf
    cat << 'EOF' > /app/backup.conf
# BACKUP PIPELINE CONFIGURATION
# The stream filter must read stdin using exactly this buffer size.
BUFFER_SIZE=12
EOF

    # Create evidence.mp4
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=3 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf:text='echo \"MALWARE_SIG_2024\" > payload.bin':fontcolor=green:fontsize=24:x=10:y=10:enable='between(t,1.4,1.6)'" -vcodec libx264 -y /app/evidence.mp4

    # Populate clean corpus
    dd if=/dev/urandom of=/app/corpus/clean/file1.bin bs=1024 count=1
    echo "This is a safe file without the signature." > /app/corpus/clean/file2.txt
    dd if=/dev/zero of=/app/corpus/clean/file3.bin bs=64 count=1

    # Populate evil corpus
    printf "12345MALWARE_SIG_2024_END_DATA" > /app/corpus/evil/file1.bin
    printf "12345678901MALWARE_SIG_2024_END" > /app/corpus/evil/file2.bin

    # Set permissions on /app so the agent can access it easily
    chmod -R 755 /app

    # Create user and set home directory permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
