#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc
    pip3 install pytest

    mkdir -p /app/corpus
    mkdir -p /app/verifier_corpus/clean
    mkdir -p /app/verifier_corpus/evil

    # Create the vulnerable C parser
    cat << 'EOF' > /tmp/parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void parse(const char *filename) {
    FILE *f = fopen(filename, "r");
    if (!f) return;
    char line[256];
    char signature[64];
    int in_sig = 0;
    char sig_buf[1024] = {0};
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "Signature:", 10) == 0) {
            in_sig = 1;
            strcat(sig_buf, line + 10);
        } else if (in_sig && (line[0] == ' ' || line[0] == '\t')) {
            strcat(sig_buf, line);
        } else {
            if (in_sig) {
                strcpy(signature, sig_buf);
                in_sig = 0;
            }
        }
    }
    if (in_sig) strcpy(signature, sig_buf);
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc > 1) parse(argv[1]);
    return 0;
}
EOF

    gcc -fno-stack-protector -O0 -o /app/legacy_doc_parser /tmp/parser.c
    strip /app/legacy_doc_parser

    # Generate corpora
    mkdir -p /tmp/clean_corpus
    mkdir -p /tmp/evil_corpus

    cat << 'EOF' > /tmp/clean_corpus/clean1.doclog
Author: Alice
Date: 2023-01-01
Signature: short-and-safe
Body:
This is a clean document.
EOF

    cat << 'EOF' > /tmp/clean_corpus/clean2.doclog
Author: Bob
Date: 2023-01-02
Body:
This document has no signature.
EOF

    cat << 'EOF' > /tmp/evil_corpus/evil1.doclog
Author: Eve
Date: 2023-01-03
Signature: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
Body:
This signature is too long and will crash the parser.
EOF

    cat << 'EOF' > /tmp/evil_corpus/evil2.doclog
Author: Mallory
Date: 2023-01-04
Signature: AAAA
 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
Body:
This signature is folded and too long, it will crash the parser.
EOF

    tar -czf /app/corpus/clean.tar.gz -C /tmp/clean_corpus .
    tar -czf /app/corpus/evil.tar.gz -C /tmp/evil_corpus .

    cp -r /tmp/clean_corpus/* /app/verifier_corpus/clean/
    cp -r /tmp/evil_corpus/* /app/verifier_corpus/evil/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
