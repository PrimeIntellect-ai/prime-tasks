#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /home/user/etl_project/data/raw
    mkdir -p /home/user/etl_project/bin
    mkdir -p /home/user/etl_project/logs

    cat << 'EOF' > /tmp/legacy_norm.c
#include <stdio.h>
#include <ctype.h>
#include <string.h>

void process_word(char* word) {
    char buffer[1024];
    int len = 0;
    for(int i=0; word[i]; i++) {
        if(isalnum(word[i])) {
            buffer[len++] = toupper(word[i]);
        }
    }
    for(int i=0; i<len; i++) {
        putchar(buffer[len-1-i]);
    }
    if(len > 0) putchar(' ');
}

int main() {
    char word[1024];
    while(scanf("%1023s", word) == 1) {
        process_word(word);
    }
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_norm.c -o /home/user/etl_project/bin/legacy_norm
    strip /home/user/etl_project/bin/legacy_norm
    chmod +x /home/user/etl_project/bin/legacy_norm

    cat << 'EOF' > /home/user/etl_project/data/raw/file1.txt
Apple banana. Apple cherry!
EOF

    cat << 'EOF' > /home/user/etl_project/data/raw/file2.txt
Banana dog elephant! dog.
EOF

    cat << 'EOF' > /home/user/etl_project/data/reference.csv
normalized_word,category
ELPPA,fruit
ANANAB,fruit
YRREHC,fruit
GOD,animal
TNAHPELE,animal
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
