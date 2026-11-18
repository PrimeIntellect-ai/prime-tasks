#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo gcc make curl libmicrohttpd-dev
    pip3 install pytest

    # Create user and setup sudo
    useradd -m -s /bin/bash user || true
    echo "user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

    # Create data directory
    mkdir -p /home/user/data

    # Generate CSV files
    cat << 'EOF' > /tmp/generate_data.py
import csv
import random

random.seed(42)
with open('/home/user/data/nodes.csv', 'w') as f:
    f.write('node_id,node_type\n')
    for i in range(1, 201):
        f.write(f'{i},{random.choice(["Person", "Company", "Project"])}\n')

with open('/home/user/data/edges.csv', 'w') as f:
    f.write('src_id,dst_id,relation_type\n')
    for _ in range(500):
        src = random.randint(1, 200)
        dst = random.randint(1, 200)
        rel = random.choice(["WorksFor", "Owns", "ContributesTo"])
        f.write(f'{src},{dst},{rel}\n')
EOF
    python3 /tmp/generate_data.py

    # Create oracle C program
    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    char *edges_file = argv[1];
    char *nodes_file = argv[2];
    char *node_id = argv[3];

    FILE *f = fopen(edges_file, "r");
    if (!f) return 1;

    char line[256];
    int in_degree = 0;
    int out_degree = 0;

    while (fgets(line, sizeof(line), f)) {
        char src[128], dst[128], rel[128];
        if (sscanf(line, "%[^,],%[^,],%s", src, dst, rel) == 3) {
            if (strcmp(src, node_id) == 0) out_degree++;
            if (strcmp(dst, node_id) == 0) in_degree++;
        }
    }
    fclose(f);

    int score = (in_degree * 3) + (out_degree * 2);
    printf("%d\n", score);
    return 0;
}
EOF
    gcc -O2 -o /app/kg_oracle /tmp/oracle.c
    strip /app/kg_oracle

    # Cleanup
    rm /tmp/generate_data.py /tmp/oracle.c

    chmod -R 777 /home/user
