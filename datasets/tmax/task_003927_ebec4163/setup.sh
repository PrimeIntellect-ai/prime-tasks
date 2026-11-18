#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils logrotate
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/legacy.c
#include <stdio.h>
#include <stdlib.h>

int main() {
    int key = fgetc(stdin);
    if (key == EOF) return 0;

    int c;
    while ((c = fgetc(stdin)) != EOF) {
        if (c == 0xAA) {
            int count = fgetc(stdin);
            if (count == EOF) break;
            int val = fgetc(stdin);
            if (val == EOF) break;
            int out = val ^ key;
            for (int i = 0; i < count; i++) {
                fputc(out, stdout);
            }
        } else {
            fputc(c ^ key, stdout);
        }
    }
    return 0;
}
EOF

gcc -O2 -o /app/legacy_decode /app/legacy.c
strip /app/legacy_decode
rm /app/legacy.c

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
