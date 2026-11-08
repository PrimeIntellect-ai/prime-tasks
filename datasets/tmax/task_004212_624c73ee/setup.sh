#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gdb ltrace
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    cat << 'EOF' > /tmp/legacy_checker.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    char *buf = malloc(size + 1);
    if (!buf) { fclose(f); return 1; }
    size_t read_bytes = fread(buf, 1, size, f);
    buf[size] = '\0';
    fclose(f);

    if (size < 5 || strncmp(buf, "BILD\n", 5) != 0) return 1;

    int nl_count = 0;
    for (long i = 0; i < size; i++) {
        if (buf[i] == '\n') nl_count++;
    }
    if (nl_count != 5) return 1;

    if (strstr(buf, "DEBUG=1") != NULL) return 1;

    free(buf);
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_checker.c -o /app/legacy_checker
    strip /app/legacy_checker
    rm /tmp/legacy_checker.c

    python3 -c '
import os
import random

clean_dir = "/app/corpora/clean"
evil_dir = "/app/corpora/evil"

for i in range(50):
    with open(os.path.join(clean_dir, f"clean_{i}.txt"), "w") as f:
        f.write("BILD\nline1\nline2\nline3\nline4\n")

for i in range(50):
    with open(os.path.join(evil_dir, f"evil_{i}.txt"), "w") as f:
        choice = random.randint(0, 2)
        if choice == 0:
            f.write("BILDX\nline1\nline2\nline3\nline4\n")
        elif choice == 1:
            f.write("BILD\nline1\nline2\nline3\nline4\nline5\n")
        else:
            f.write("BILD\nline1\nDEBUG=1\nline3\nline4\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
