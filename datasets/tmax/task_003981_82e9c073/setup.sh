#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick fonts-dejavu-core gcc libc6-dev
    pip3 install pytest

    # Create the image
    mkdir -p /app
    convert -size 400x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black \
      -draw "text 20,50 'TZ: Europe/Berlin'" \
      -draw "text 20,100 'MAGIC_BYTE: 170'" \
      /app/config.png

    # Create the oracle program
    cat << 'EOF' > /app/oracle_processor.c
#include <stdio.h>
#include <unistd.h>

int main() {
    int c;
    int magic = 170;
    while ((c = getchar()) != EOF) {
        if (c >= '0' && c <= '9') {
            putchar(c);
        } else {
            putchar(c ^ magic);
        }
    }
    return 0;
}
EOF
    gcc -O2 /app/oracle_processor.c -o /app/oracle_processor
    chmod +x /app/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
