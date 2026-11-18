#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    useradd -s /bin/false alice || true

    mkdir -p /app /app/evaluation_corpus/clean /app/evaluation_corpus/evil
    mkdir -p /home/user/training_corpus/clean /home/user/training_corpus/evil

    cat << 'EOF' > /tmp/legacy_mailer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[2048];
    int has_from = 0;
    int in_body = 0;

    while (fgets(line, sizeof(line), f)) {
        if (!in_body) {
            if (strncmp(line, "From:", 5) == 0) {
                has_from = 1;
            } else if (strncmp(line, "Subject:", 8) == 0) {
                char *val = line + 8;
                while (*val == ' ') val++;
                int len = strlen(val);
                if (len > 0 && val[len-1] == '\n') len--;
                if (len > 80) {
                    char *p = NULL;
                    *p = 1;
                }
            } else if (line[0] == '\n' || (line[0] == '\r' && line[1] == '\n')) {
                in_body = 1;
            }
        } else {
            if (line[0] == '.' && isalnum(line[1])) {
                while(1) {}
            }
        }
    }
    fclose(f);

    if (!has_from) {
        abort();
    }
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_mailer.c -o /app/legacy_mailer
    strip /app/legacy_mailer
    chmod +x /app/legacy_mailer
    rm /tmp/legacy_mailer.c

    # Clean corpus
    cat << 'EOF' > /home/user/training_corpus/clean/email1.eml
From: bob@example.com
To: alice@example.com
Subject: Hello

This is a safe email.
EOF

    cat << 'EOF' > /app/evaluation_corpus/clean/email1.eml
From: charlie@example.com
To: user@example.com
Subject: Safe subject

Another safe email.
EOF

    # Evil corpus
    cat << 'EOF' > /home/user/training_corpus/evil/evil1.eml
To: alice@example.com
Subject: Missing From

This will abort.
EOF

    cat << 'EOF' > /home/user/training_corpus/evil/evil2.eml
From: bob@example.com
To: alice@example.com
Subject: This subject is extremely long and will definitely exceed the eighty character limit causing a crash

This will segfault.
EOF

    cat << 'EOF' > /home/user/training_corpus/evil/evil3.eml
From: bob@example.com
To: alice@example.com
Subject: Bad body

.badline
This will hang.
EOF

    cat << 'EOF' > /home/user/training_corpus/evil/evil4.eml
From: bob@example.com
To: non_existent_user@example.com
Subject: Bad To

Policy violation.
EOF

    cat << 'EOF' > /app/evaluation_corpus/evil/evil1.eml
To: alice@example.com
Subject: Missing From again

Abort.
EOF

    chmod -R 777 /home/user
