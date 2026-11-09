#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make golang-go ffmpeg
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Task 1 setup
    mkdir -p /home/user/log_tool
    cat << 'EOF' > /home/user/log_tool/process_log.c
#include <stdio.h>
int main() {
    printf("Log processed.\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/log_tool/Makefile
all:
    gcc process_log.c
EOF

    # Task 2 setup
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    echo "This is a clean log." > /app/corpus/clean/clean1.log
    printf "This is a clean log\twith tabs\r\nand carriage returns.\n" > /app/corpus/clean/clean2.log

    printf "Evil log with \x00 null byte.\n" > /app/corpus/evil/evil1.log
    printf "Evil log with invalid UTF-8 \xFF\xFE.\n" > /app/corpus/evil/evil2.log

    # Create evil3.log with a line > 2000 bytes
    python3 -c "print('A' * 2005)" > /app/corpus/evil/evil3.log

    printf "Evil log with \x1b[31m ANSI escape code.\n" > /app/corpus/evil/evil4.log

    # Task 3 setup
    # Generate a 10s 30fps white video, with frame 141 (0-based, so 142nd frame) being red.
    ffmpeg -y -f lavfi -i color=c=white:s=320x240:r=30:d=10 -vf "drawbox=x=0:y=0:w=320:h=240:color=red@1:t=fill:enable='eq(n\,141)'" -c:v libx264 -preset ultrafast /app/test_run.mp4

    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
