#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        imagemagick \
        fonts-dejavu-core \
        gcc \
        make

    pip3 install --default-timeout=100 pytest

    mkdir -p /app/clean /app/evil

    echo 'server-alpha 86000.0 86400.0' > /app/clean/clean_1.txt
    echo 'db_node_02 86399.0 86400.0' > /app/clean/clean_2.txt

    echo 'server alpha 86000 86400' > /app/evil/evil_1.txt
    echo 'db-node;rm 86000 86400' > /app/evil/evil_2.txt
    echo 'web-node 86399.9999999999999999 86400.0' > /app/evil/evil_3.txt
    echo 'cache-node 90000.0 86400.0' > /app/evil/evil_4.txt

    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 14 -fill black -draw "text 10,50 'ALERT: False 100% uptime detected due to double-precision rounding. Reject logs where uptime_seconds < total_seconds but the computed percentage (uptime/total)*100.0 evaluates to exactly 100.0. Valid filename chars: A-Z, a-z, 0-9, dash, underscore. No spaces or shell chars!'" /app/graph_alert.png

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/sanitizer.c
#include <stdlib.h>
int main() {
    char filename[256];
    double uptime, total;
    if (scanf("%255s %lf %lf", filename, &uptime, &total) != 3) return 1;
    /* implementation needed */
    return 0;
}
EOF

    printf "sanitizer: sanitizer.c\n\tgcc -std=c99 -Wall -Werror -Wimplicit-function-declaration -o sanitizer sanitizer.c\n" > /home/user/Makefile

    chmod -R 777 /home/user
    chmod -R 777 /app
