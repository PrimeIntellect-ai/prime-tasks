#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc make
    pip3 install pytest

    # Create reference encoder
    mkdir -p /app
    cat << 'EOF' > /app/encoder.c
#include <stdio.h>

int main() {
    unsigned char buf[8192];
    size_t len = fread(buf, 1, sizeof(buf), stdin);
    if (len == 0) return 0;
    size_t i = 0;
    while (i < len) {
        unsigned char c = buf[i];
        int count = 1;
        while (i + count < len && buf[i+count] == c && count < 255) {
            count++;
        }
        putchar(count ^ 0x5A);
        putchar(c ^ 0x5A);
        i += count;
    }
    return 0;
}
EOF
    gcc -O2 /app/encoder.c -o /app/reference_encoder
    strip /app/reference_encoder
    rm /app/encoder.c

    # Create git repository
    mkdir -p /home/user/metric_agent
    cd /home/user/metric_agent
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Commit 1: Initial implementation
    cat << 'EOF' > encoder.c
#include <stdio.h>

int main() {
    unsigned char buf[8192];
    size_t len = fread(buf, 1, sizeof(buf), stdin);
    if (len == 0) return 0;
    size_t i = 0;
    while (i < len) {
        unsigned char c = buf[i];
        int count = 1;
        while (i + count < len && buf[i+count] == c && count < 255) {
            count++;
        }
        putchar(count ^ 0x5A);
        putchar(c ^ 0x5A);
        i += count;
    }
    return 0;
}
EOF
    git add encoder.c
    git commit -m "Commit 1: Initial implementation of the RLE + XOR algorithm"

    # Commit 2: Added logging
    echo "// Added some logging features" >> encoder.c
    git commit -am "Commit 2: Added some logging features"

    # Commit 3: Buggy refactor
    cat << 'EOF' > encoder.c
#include <stdio.h>

int main() {
    unsigned char buf[8192];
    size_t len = fread(buf, 1, sizeof(buf), stdin);
    if (len == 0) return 0;
    size_t i = 0;
    while (i < len) {
        unsigned char c = buf[i];
        int count = 1;
        while (i + count < len && buf[i+count] == c && count < 255) {
            if (count <= 3) {
                count++;
            }
        }
        putchar(count ^ 0x5A);
        putchar(c ^ 0x5A);
        i += count;
    }
    return 0;
}
EOF
    git commit -am "Commit 3: Refactor loop logic"

    # Commit 4: Unrelated formatting changes
    echo "// formatting changes" >> encoder.c
    git commit -am "Commit 4: Unrelated formatting changes"

    # Commit 5: More unrelated changes
    echo "// more unrelated changes" >> encoder.c
    git commit -am "Commit 5: More unrelated changes"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
