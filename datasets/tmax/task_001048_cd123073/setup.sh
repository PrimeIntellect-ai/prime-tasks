#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/data.csv
id,timestamp
1,1600000000
2,1600000001
3,3000000000
4,4000000000
5,500000000000
EOF

    cat << 'EOF' > /home/user/etl.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];
    FILE *in = fopen("/home/user/data.csv", "r");
    FILE *out = fopen("/home/user/data_clean.csv", "w");
    if (!in || !out) return 1;

    // Read header
    if (fgets(line, sizeof(line), in)) {
        fprintf(out, "%s", line);
    }

    while (fgets(line, sizeof(line), in)) {
        char *id_str = strtok(line, ",");
        char *val_str = strtok(NULL, "\n");
        if (id_str && val_str) {
            int id = atoi(id_str);
            int val = atoi(val_str);
            fprintf(out, "%d,%d\n", id, val);
        }
    }
    fclose(in);
    fclose(out);
    return 0;
}
EOF

    chmod -R 777 /home/user
