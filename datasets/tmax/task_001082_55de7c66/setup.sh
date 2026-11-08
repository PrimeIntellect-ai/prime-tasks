#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc ffmpeg
    pip3 install pytest

    mkdir -p /app/src /app/bin

    # Create oracle source and compile
    cat << 'EOF' > /app/src/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    int c;
    while ((c = fgetc(f)) != EOF) {
        putchar((c ^ 0x4A) + 0x07);
    }
    fclose(f);
    return 0;
}
EOF
    gcc /app/src/oracle.c -o /app/bin/oracle
    strip /app/bin/oracle
    rm /app/src/oracle.c

    # Create recover.c
    cat << 'EOF' > /app/src/recover.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    int c;
    while ((c = fgetc(f)) != EOF) {
        int in_byte = c;
        int out_byte = in_byte; // FIXME
        putchar(out_byte);
    }
    fclose(f);
    return 0;
}
EOF

    # Create video
    echo "DEBUG: Applying recovery mask: out_byte = (in_byte ^ 0x4A) + 0x07;" > /tmp/text.txt
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=5 -vf "drawtext=textfile=/tmp/text.txt:fontcolor=white:fontsize=24:x=10:y=50" -c:v libx264 -pix_fmt yuv420p -y /app/debug_session.mp4
    rm /tmp/text.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
