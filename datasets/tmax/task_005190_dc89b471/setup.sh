#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential binutils gawk grep sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/vendored-tracker-1.2

    cat << 'EOF' > /app/vendored-tracker-1.2/Makefile
all: setup

setup: generator
	mkdir -p /home/user/test_elfs
	./generator /home/user/test_elfs

generator: generator.c
	sed -i '' 's/DUMMY/CONFIG/g' generator.c
	gcc -o generator generator.c
EOF

    cat << 'EOF' > /app/vendored-tracker-1.2/generator.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    char cmd[256];
    sprintf(cmd, "touch %s/test1.elf %s/test2.elf", argv[1], argv[1]);
    system(cmd);
    // DUMMY
    return 0;
}
EOF

    chmod -R 777 /app/vendored-tracker-1.2
    chmod -R 777 /home/user
