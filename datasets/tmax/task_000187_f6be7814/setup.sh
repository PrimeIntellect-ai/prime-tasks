#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg fonts-dejavu-core e2fsprogs g++
    pip3 install pytest

    mkdir -p /app/corpus/evil /app/corpus/clean
    echo "file with space.txt" > /app/corpus/evil/1.txt
    echo "file;rm -rf /" > /app/corpus/evil/2.txt
    echo "file$(whoami)" > /app/corpus/evil/3.txt
    echo -e "file\nname.txt" > /app/corpus/evil/4.txt

    echo "file_without_space.txt" > /app/corpus/clean/1.txt
    echo "normal-file-name.log" > /app/corpus/clean/2.txt
    echo "archive.2024.tar.gz" > /app/corpus/clean/3.txt

    # Generate the dashboard video recording
    echo 'FATAL: Shell parser exception at 2024-05-12 09:15:33' > /tmp/text.txt
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=10 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:textfile=/tmp/text.txt:fontcolor=white:fontsize=24:x=10:y=10:enable='between(t,4,10)'" \
        -c:v libx264 -pix_fmt yuv420p /app/dashboard_record.mp4

    # Generate the ext4 image and simulate file deletion
    mkdir -p /tmp/mnt
    cat << 'EOF' > /tmp/mnt/system.log
2024-05-12 09:15:30 INFO Processing normal_file.txt
2024-05-12 09:15:31 INFO Processing normal-file-name.log
2024-05-12 09:15:33 ERROR Malformed payload: /var/drop/payload; rm -rf /; echo "hacked"
2024-05-12 09:15:34 INFO Restarting service...
EOF

    dd if=/dev/zero of=/app/log_volume.img bs=1M count=32
    mkfs.ext4 -d /tmp/mnt /app/log_volume.img
    # Delete the file without mounting to avoid permission issues in build environments
    debugfs -w -R "rm system.log" /app/log_volume.img

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
