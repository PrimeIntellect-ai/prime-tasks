#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    # Create app directory and binary
    mkdir -p /app
    cat << 'EOF' > /app/doc_builder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[4096];
    size_t bytes_read = fread(buffer, 1, 4096, stdin);
    if (bytes_read > 2048) {
        int *p = NULL;
        *p = 1; // Intentional segfault
    }
    for(size_t i=0; i<bytes_read; i++) {
        if(buffer[i] == '*') {
            printf("<i>");
            i++;
            while(i<bytes_read && buffer[i] != '*') {
                putchar(buffer[i]);
                i++;
            }
            if(i<bytes_read) printf("</i>");
        } else {
            putchar(buffer[i]);
        }
    }
    return 0;
}
EOF
    gcc -o /app/doc_builder /app/doc_builder.c
    strip /app/doc_builder
    rm /app/doc_builder.c

    # Create directories
    mkdir -p /home/user/docs/assets
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    # Create config
    cat << 'EOF' > /home/user/docs_config.ini
[Security]
AllowedAssetDir = /home/user/docs/assets
EOF

    # Create assets
    echo "This is a safe snippet." > /home/user/docs/assets/snippet1.txt
    echo "Another safe snippet." > /home/user/docs/assets/snippet2.txt

    # Create malicious symlinks in assets
    ln -s /etc/shadow /home/user/docs/assets/symlink_out.txt
    ln -s /home/user/docs/assets/loop.txt /home/user/docs/assets/loop.txt

    # Create clean corpus
    for i in $(seq 1 10); do
        echo "Clean document $i with *formatting* and include: [[INCLUDE_ASSET: snippet1.txt]]" > /home/user/corpus/clean/clean_$i.md
    done

    # Create evil corpus
    echo "Evil 1: [[INCLUDE_ASSET: ../../../../../etc/passwd]]" > /home/user/corpus/evil/evil_1.md
    echo "Evil 2: [[INCLUDE_ASSET: symlink_out.txt]]" > /home/user/corpus/evil/evil_2.md
    echo "Evil 3: [[INCLUDE_ASSET: loop.txt]]" > /home/user/corpus/evil/evil_3.md

    # Create a chain of hardlinks for evil_4
    touch /home/user/outside_file.txt
    ln /home/user/outside_file.txt /home/user/docs/assets/hardlink.txt
    echo "Evil 4: [[INCLUDE_ASSET: hardlink.txt]]" > /home/user/corpus/evil/evil_4.md

    for i in $(seq 5 10); do
        echo "Evil $i: [[INCLUDE_ASSET: ../../../../../etc/shadow]]" > /home/user/corpus/evil/evil_$i.md
    done

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
