#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git gcc strace libc-dev
    pip3 install pytest

    mkdir -p /home/user/log_processor
    cd /home/user/log_processor
    git init

    cat << 'EOF' > parser.c
#include <stdio.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc < 2) {
        return 1;
    }

    FILE* f = fopen("/tmp/auth.key", "r");
    if (!f) return 1;

    char key[32] = {0};
    if (fscanf(f, "%31s", key) != 1) {
        fclose(f);
        return 1;
    }
    fclose(f);

    if (strcmp(key, "auth_secret_998877abc") != 0) {
        return 2;
    }

    FILE* data = fopen(argv[1], "r");
    if (!data) return 3;

    char line[256];
    int sum = 0;

    while (fgets(line, sizeof(line), data)) {
        int a, b, c;
        // Vulnerable parsing and math logic
        sscanf(line, "%d,%d,%d", &a, &b, &c);
        sum += (a * b) / c;
    }

    printf("Total: %d\n", sum);
    fclose(data);
    return 0;
}
EOF

    cat << 'EOF' > data.log
10,5,2
100,2,10
CORRUPTED_LOG_LINE_MISSING_DATA
50,2,0
8,8,4
12,X,3
EOF

    gcc -o log_calc parser.c

    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    git add parser.c data.log
    git commit -m "Initial commit of parser and sample data"

    cat << 'EOF' > dev_notes.txt
TODO: Move this key to a secure vault: auth_secret_998877abc
EOF
    git add dev_notes.txt
    git commit -m "Add temporary dev notes with auth key"

    git rm dev_notes.txt
    git commit -m "Remove hardcoded secret key"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
