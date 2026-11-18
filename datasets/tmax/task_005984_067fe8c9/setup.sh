#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/etl_project

    cat << 'EOF' > /home/user/etl_project/interactions.csv
user_id,item_id,rating
1,101,4
1,102,?
2,101,3
2,102,5
2,103,?
3,101,?
3,102,2
EOF

    cat << 'EOF' > /home/user/etl_project/etl.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    // Buggy initial code
    FILE *f = fopen("interactions.csv", "r");
    char line[256];
    fgets(line, sizeof(line), f); // skip header

    int u, i;
    float r;
    while (fgets(line, sizeof(line), f)) {
        sscanf(line, "%d,%d,%f", &u, &i, &r);
        // Does nothing with it right now
    }
    fclose(f);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
