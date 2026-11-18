#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gcc make gdb binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /app/samples

    cat << 'EOF' > /app/legacy_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char user[256];
    char action[256];
    char data[1024];

    if (scanf("USER: %255s\n", user) != 1) return 1;
    if (scanf("ACTION: %255s\n", action) != 1) return 1;
    if (scanf("DATA: %1023[^\n]\n", data) != 1) return 1;

    char cmd[2048];
    sprintf(cmd, "echo 'Processing %s for %s' > /dev/null", data, user);
    system(cmd);

    return 0;
}
EOF
    gcc -O2 -o /app/legacy_processor /app/legacy_processor.c
    strip /app/legacy_processor
    rm /app/legacy_processor.c

    for i in $(seq 1 50); do
        cat << EOF > /app/corpus/clean/clean_$i.txt
USER: testuser$i
ACTION: READ
DATA: some safe data $i
EOF
    done

    for i in $(seq 1 50); do
        cat << EOF > /app/corpus/evil/evil_$i.txt
USER: testuser$i
ACTION: READ
DATA: some safe data $i ; rm -rf /
EOF
    done

    cp /app/corpus/clean/clean_1.txt /app/samples/sample_clean_1.txt
    cp /app/corpus/clean/clean_2.txt /app/samples/sample_clean_2.txt
    cp /app/corpus/evil/evil_1.txt /app/samples/sample_evil_1.txt
    cp /app/corpus/evil/evil_2.txt /app/samples/sample_evil_2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
