#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install necessary packages for setup and agent tools
    apt-get install -y ffmpeg fonts-dejavu-core tesseract-ocr e2fsprogs binutils gcc coreutils grep bash

    mkdir -p /app

    # 1. Generate /app/crash_capture.mp4
    # Create a 5-second video at 30fps. On frame 75, render the text.
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='ERR_CODE\: 0x8F4A':x=(w-text_w)/2:y=(h-text_h)/2:fontsize=48:fontcolor=white:enable='eq(n\,75)'" -r 30 -c:v libx264 -pix_fmt yuv420p /app/crash_capture.mp4

    # 2. Create /app/system_disk.ext4 and the deleted file
    mkdir -p /tmp/ext4_root
    cat << 'EOF' > /tmp/ext4_root/session_map.txt
0x1A2B -> PAYLOAD_ID: 10
0x8F4A -> PAYLOAD_ID: 99
0x9C3D -> PAYLOAD_ID: 45
EOF
    # Create the ext4 image populated with the directory contents
    mke2fs -t ext4 -d /tmp/ext4_root /app/system_disk.ext4 10M
    # Delete the file using debugfs so it can be recovered
    debugfs -w -R "rm session_map.txt" /app/system_disk.ext4

    # 3. Compile /app/log_formatter.elf
    cat << 'EOF' > /tmp/log_formatter.c
#include <stdio.h>
int main() {
    printf("[CRITICAL_FAULT] EXPLOIT_TRIGGERED_WITH_ID_%s_ABORTING\n", "test");
    return 0;
}
EOF
    gcc -o /app/log_formatter.elf /tmp/log_formatter.c
    strip /app/log_formatter.elf

    # 4. Generate the /app/corpus/evil/ and /app/corpus/clean/ text files
    mkdir -p /app/corpus/evil /app/corpus/clean
    for i in $(seq 1 50); do
        # Evil files
        echo "INFO: Service started" > /app/corpus/evil/log_${i}.txt
        echo "DEBUG: Processing request" >> /app/corpus/evil/log_${i}.txt
        echo "[CRITICAL_FAULT] EXPLOIT_TRIGGERED_WITH_ID_99_ABORTING" >> /app/corpus/evil/log_${i}.txt

        # Clean files
        echo "INFO: Service started" > /app/corpus/clean/log_${i}.txt
        echo "DEBUG: Processing request" >> /app/corpus/clean/log_${i}.txt
        if [ $((i % 2)) -eq 0 ]; then
            echo "[CRITICAL_FAULT] EXPLOIT_TRIGGERED_WITH_ID_10_ABORTING" >> /app/corpus/clean/log_${i}.txt
        else
            echo "INFO: Request successful" >> /app/corpus/clean/log_${i}.txt
        fi
    done

    # Clean up temp files
    rm -rf /tmp/ext4_root /tmp/log_formatter.c

    # Create the user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
