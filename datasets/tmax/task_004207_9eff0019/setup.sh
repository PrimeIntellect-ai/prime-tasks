#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-liberation \
        gcc

    pip3 install pytest

    mkdir -p /home/user/src /home/user/bin /home/user/nginx/conf /home/user/nginx/logs /app

    # Generate the image fixture
    convert -size 400x100 xc:white -fill black -pointsize 24 -gravity center -draw "text 0,0 'TOKEN: GAMMA77'" /app/token_spec.png

    # Generate the Oracle C program
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *str = argv[1];
    int len = strlen(str);
    printf("PROCESSED: ");
    for (int i = len - 1; i >= 0; i--) {
        putchar(str[i]);
    }
    printf(" | AUTH: GAMMA77\n");
    return 0;
}
EOF

    # Compile the oracle
    gcc -O3 /app/oracle.c -o /app/oracle_processor

    # Create dummy Nginx config
    cat << 'EOF' > /home/user/nginx/conf/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /process {
            fastcgi_pass 127.0.0.1:9099; # BROKEN PORT
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
