#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    cd /home/user/project

    cat << 'EOF' > extractor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char filename[256];
    int size;
    while (scanf("%255s %d\n", filename, &size) == 2) {
        FILE *f = fopen(filename, "wb");
        if (!f) {
            // If we can't open, just consume to not break stream
            for (int i = 0; i < size; i++) getchar();
            continue;
        }
        for (int i = 0; i < size; i++) {
            fputc(getchar(), f);
        }
        fclose(f);
    }
    return 0;
}
EOF

    printf "../secret.txt 12\nHACKED_DATA!" > raw_archive.bin
    printf "backup.conf 15\napp.log\nmain.c\n" >> raw_archive.bin
    printf "app.log 12\nhello world\n" >> raw_archive.bin
    printf "main.c 13\nint main(){}\n" >> raw_archive.bin

    gzip -c raw_archive.bin > archive.gz
    rm raw_archive.bin

    echo "SAFE" > /home/user/secret.txt

    chmod -R 777 /home/user
