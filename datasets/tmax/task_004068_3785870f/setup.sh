#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/diff_encoder.c
#include <stdio.h>
#include <string.h>

int main() {
    unsigned char buf[16];
    size_t n;
    while ((n = fread(buf, 1, 16, stdin)) > 0) {
        if (n < 16) {
            memset(buf + n, 0, 16 - n);
        }
        unsigned char out[16];
        for (int i = 0; i < 16; i++) {
            out[i] = buf[15 - i] ^ 0x5A;
        }
        fwrite(out, 1, 16, stdout);
    }
    return 0;
}
EOF
    gcc -O2 /app/diff_encoder.c -o /app/diff_encoder
    strip /app/diff_encoder
    rm /app/diff_encoder.c

    mkdir -p /home/user/legacy_configs/dir1
    mkdir -p /home/user/legacy_configs/dir2

    python3 -c "
with open('/home/user/legacy_configs/dir1/a.conf', 'w', encoding='iso-8859-1') as f:
    f.write('key1=value1\nkey2=résumé\n')
with open('/home/user/legacy_configs/dir2/b.conf', 'w', encoding='utf-16le') as f:
    f.write('setting=enabled\npath=/var/log\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
