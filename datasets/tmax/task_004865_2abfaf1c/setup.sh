#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gcc make binutils
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Create legacy_checker source and compile
    cat << 'EOF' > /tmp/checker.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    char *filename = argv[1];
    int len = strlen(filename);
    if (len >= 4 && strcmp(filename + len - 4, ".dat") == 0) {
        FILE *f = fopen(filename, "rb");
        if (f) {
            unsigned char buf[4];
            if (fread(buf, 1, 4, f) == 4) {
                if (buf[0] == 0xDE && buf[1] == 0xAD && buf[2] == 0xBE && buf[3] == 0xEF) {
                    fprintf(stderr, "CORRUPTED\n");
                    fclose(f);
                    return 1;
                }
            }
            fclose(f);
        }
    }
    return 0;
}
EOF
    gcc -O2 -s /tmp/checker.c -o /app/legacy_checker
    rm /tmp/checker.c

    # Create clean corpus
    for i in $(seq 1 10); do
        d="/app/corpus/clean/dataset_$i"
        mkdir -p "$d"
        echo "clean data" > "$d/file.txt"
        echo "more data" > "$d/data.dat"
        ln -s "file.txt" "$d/link.txt"
    done

    # Create evil corpus
    for i in $(seq 1 10); do
        d="/app/corpus/evil/evil_$i"
        mkdir -p "$d"
        if [ $i -le 5 ]; then
            # Symlink loop
            ln -s "loop" "$d/loop"
        else
            # Corrupted file
            printf '\xDE\xAD\xBE\xEFbad data' > "$d/bad.dat"
        fi
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
