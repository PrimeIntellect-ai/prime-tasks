#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        gcc \
        gawk \
        fonts-dejavu-core

    pip3 install --default-timeout=100 pytest

    mkdir -p /app

    # Generate the dev_note.png
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 10,50 'SALT=x9K2mP_v2'" /app/dev_note.png

    # Create the legacy_token_gen oracle
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "echo -n '%sx9K2mP_v2' | sha256sum | awk '{print $1}'", argv[1]);
    system(cmd);
    return 0;
}
EOF
    gcc -O2 /tmp/oracle.c -o /app/legacy_token_gen
    strip /app/legacy_token_gen
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
