#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project
    mkdir -p /home/user/artifacts

    cat << 'EOF' > /home/user/project/artifact_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int limit = atoi(argv[1]);

    char *line = malloc(256);
    if (!line) return 1;

    if (fgets(line, 256, stdin)) {
        int size = 0;
        if (sscanf(line, "size: %d", &size) == 1) {
            if (size < limit) {
                printf("PASS\n");
                return 0;
            }
        }
    }
    printf("FAIL\n");
    return 1;
}
EOF

    cat << 'EOF' > /home/user/project/Makefile
all: artifact_filter

artifact_filter: artifact_filter.c
    gcc -o artifact_filter artifact_filter.c

clean:
    rm -f artifact_filter
EOF

    echo "size: 500" > /home/user/artifacts/art1.txt
    echo "size: 1200" > /home/user/artifacts/art2.txt
    echo "size: 999" > /home/user/artifacts/art3.txt
    echo "size: 1000" > /home/user/artifacts/art4.txt

    chown -R user:user /home/user/project /home/user/artifacts
    chmod -R 777 /home/user
