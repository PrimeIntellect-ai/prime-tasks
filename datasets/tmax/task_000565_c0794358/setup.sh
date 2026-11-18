#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_validator.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    char *str = argv[1];
    if (strlen(str) > 500) return 1;
    for (int i = 0; i < strlen(str) - 2; i++) {
        if ((unsigned char)str[i] == 0xed && (unsigned char)str[i+1] >= 0xa0 && (unsigned char)str[i+1] <= 0xbf) {
            return 1;
        }
    }
    return 0;
}
EOF
    gcc -O2 /app/legacy_validator.c -o /app/legacy_validator
    strip /app/legacy_validator
    rm /app/legacy_validator.c

    mkdir -p /truth/evil_corpus /truth/clean_corpus
    cat << 'EOF' > /truth/evil_corpus/evil_1.json
[
  {"id": "1", "lang": "en", "text": "Valid text"},
  {"id": "2", "lang": "en", "text": "Invalid \ud800 text"}
]
EOF

    cat << 'EOF' > /truth/clean_corpus/clean_1.json
[
  {"id": "1", "lang": "en", "text": "Clean text 1"},
  {"id": "2", "lang": "fr", "text": "Texte propre 2"}
]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
