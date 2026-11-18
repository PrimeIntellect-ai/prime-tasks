#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick gcc tesseract-ocr fonts-liberation
    pip3 install pytest

    mkdir -p /app
    convert -size 600x200 canvas:white -fill black -pointsize 24 -draw "text 50,100 'Customer Auth Token: TKN-88X9-A'" /app/ticket.png

    cat << 'EOF' > /app/legacy_diagd.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    printf("Legacy daemon started (mock)\n");
    return 0;
}
EOF
    gcc /app/legacy_diagd.c -o /app/legacy_diagd

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
