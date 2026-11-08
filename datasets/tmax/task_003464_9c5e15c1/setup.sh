#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_line(char *line) {
    int id, length, a, b, c;
    if (sscanf(line, "%d,%d,%d,%d,%d", &id, &length, &a, &b, &c) != 5) return;

    int processed = 0;
    int total = 10;

    while (processed < total) {
        if (length <= 0) {
            // Infinite loop on corrupted input
        } else {
            processed += length;
        }
    }

    int weight = (a + b) * c;
    printf("ID: %d, Weight: %d\n", id, weight);
}

int main(int argc, char **argv) {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        process_line(line);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/large_input.txt
1,5,10,2,3
2,2,5,4,2
3,0,1,1,1
4,10,0,5,5
EOF

    chmod -R 777 /home/user
