#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create the legacy_graph_oracle C source
    cat << 'EOF' > /app/legacy_graph_oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        char src[256], dst[256], type[256], amt[256];
        if (sscanf(line, "%255[^,],%255[^,],%255[^,],%255s", src, dst, type, amt) == 4) {
            if (strcmp(src, dst) == 0) {
                int *p = NULL;
                *p = 1; // Segfault
            }
            if (strlen(type) > 12 || strchr(type, ';') != NULL) {
                int *p = NULL;
                *p = 1; // Segfault
            }
        }
    }
    printf("Processed successfully.\n");
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O3 -s /app/legacy_graph_oracle.c -o /app/legacy_graph_oracle
    rm /app/legacy_graph_oracle.c

    # Generate corpora using Python
    python3 -c '
import os

for i in range(50):
    with open(f"/app/corpora/clean/clean_{i}.csv", "w") as f:
        f.write(f"node_{i},node_{i+1},TRANSFER,100\n")
        f.write(f"node_{i+1},node_{i+2},DEPOSIT,50\n")

for i in range(50):
    with open(f"/app/corpora/evil/evil_{i}.csv", "w") as f:
        if i % 3 == 0:
            f.write(f"node_{i},node_{i},TRANSFER,100\n")
        elif i % 3 == 1:
            f.write(f"node_{i},node_{i+1},VERYLONGTRANSACTION,100\n")
        else:
            f.write(f"node_{i},node_{i+1},TRANS;DROP,100\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
