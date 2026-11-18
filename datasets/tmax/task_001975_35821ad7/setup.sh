#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk bc coreutils
    pip3 install pytest

    mkdir -p /home/user/data/train_clean /home/user/data/train_evil /app/test_clean /app/test_evil

    cat << 'EOF' > /app/embedder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size == 0) {
        printf("0 0 0 0 0\n");
        return 0;
    }

    char *buf = malloc(size + 1);
    fread(buf, 1, size, f);
    buf[size] = '\0';
    fclose(f);

    int vowels = 0;
    int lines = 0;
    int spaces = 0;

    for (long i = 0; i < size; i++) {
        char c = tolower(buf[i]);
        if (c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u') vowels++;
        if (c == '\n') lines++;
        if (c == ' ') spaces++;
    }
    if (size > 0 && buf[size-1] != '\n') lines++;

    long hash = 0;
    for (long i = 0; i < size && buf[i] != '\n'; i++) {
        hash = hash * 31 + buf[i];
    }
    if (hash < 0) hash = -hash;

    int f1 = size % 100;
    int f2 = vowels % 50;
    int f3 = lines;
    int f4 = (spaces * 100) / size;
    int f5 = hash % 20;

    printf("%d %d %d %d %d\n", f1, f2, f3, f4, f5);
    free(buf);
    return 0;
}
EOF

    gcc -O2 /app/embedder.c -o /app/artifact_embedder
    strip /app/artifact_embedder
    rm /app/embedder.c

    python3 -c '
import os

def create_file(path, target_type, idx):
    if target_type == "clean":
        # Small file, few lines, few vowels, 0 spaces.
        content = "hello\nworld\n" * 2
        with open(path, "w") as f:
            f.write(content + str(idx))
    else:
        # Evil: sum > 150. Many lines.
        content = "a e i o u \n" * 160
        with open(path, "w") as f:
            f.write(content + str(idx))

for i in range(10):
    create_file(f"/home/user/data/train_clean/clean_{i}.txt", "clean", i)
    create_file(f"/app/test_clean/clean_{i}.txt", "clean", i)
    create_file(f"/home/user/data/train_evil/evil_{i}.txt", "evil", i)
    create_file(f"/app/test_evil/evil_{i}.txt", "evil", i)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
