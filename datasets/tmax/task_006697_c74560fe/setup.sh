#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/artifact_manager

    cat << 'EOF' > /home/user/artifact_manager/version_bumper.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        return 1;
    }
    int x, y, z;
    if (sscanf(argv[1], "%d.%d.%d", &x, &y, &z) != 3) {
        return 1;
    }

    if (strcmp(argv[2], "patch") == 0) {
        z++;
    } else if (strcmp(argv[2], "minor") == 0) {
        y++;
        z = 0;
    } else if (strcmp(argv[2], "major") == 0) {
        x++;
        y = 0;
        z = 0;
    } else {
        return 1;
    }

    printf("%d.%d.%d\n", x, y, z);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/artifact_manager/Makefile
CC=gcc
CFLAGS=-Wall

all: version_bumper

version_bumper: version_bumper.c
    $(CC) $(CFLAGS) -o version_bumper version_bumper.c

clean:
    rm -f version_bumper
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
