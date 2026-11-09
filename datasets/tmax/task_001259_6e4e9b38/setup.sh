#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        gcc \
        git \
        logrotate \
        fonts-liberation \
        libc6-dev

    pip3 install pytest

    mkdir -p /app

    # Generate the video with the hidden text
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=4 -vf "drawtext=fontfile=/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf:text='RATE_LIMIT=150':fontcolor=white:fontsize=24:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,2,2.1)'" -pix_fmt yuv420p /app/dashboard_recording.mp4

    # Create and compile the oracle processor
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 0;
    char *input = argv[1];
    if (strncmp(input, "[DEBUG]", 7) == 0) return 0;
    if (strstr(input, "PANIC") != NULL) return 1;
    printf("%s_RLIMIT150\n", input);
    return 0;
}
EOF
    gcc -o /app/oracle_processor /app/oracle.c
    rm /app/oracle.c

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/logs
    chmod -R 777 /home/user
