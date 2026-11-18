#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc git netcat-openbsd logrotate binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/legacy_processor.c
#include <stdio.h>
#include <ctype.h>

int main() {
    int c;
    while ((c = getchar()) != EOF) {
        if (isalpha(c)) {
            if ((c >= 'a' && c <= 'm') || (c >= 'A' && c <= 'M')) {
                putchar(c + 13);
            } else {
                putchar(c - 13);
            }
        } else if (isdigit(c)) {
            putchar('9' - (c - '0'));
        } else {
            putchar(c);
        }
    }
    return 0;
}
EOF

gcc -O2 -o /app/legacy_processor /app/legacy_processor.c
strip /app/legacy_processor
rm /app/legacy_processor.c

mkdir -p /home/user/incoming_logs /home/user/processed
echo "Hello World 123" > /home/user/incoming_logs/test1.log
echo "Migration test 456" > /home/user/incoming_logs/test2.log

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
