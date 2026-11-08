#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/dataset.csv
id,val1,val2
1,10,20
2,NA,5
3,15,NA
4,NA,NA
5,7,8
6,0,10
EOF

    cat << 'EOF' > /home/user/etl_processor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[256];

    while (fgets(line, sizeof(line), stdin)) {
        // Strip newline
        line[strcspn(line, "\n")] = 0;

        char *id_str = strtok(line, ",");
        char *v1_str = strtok(NULL, ",");
        char *v2_str = strtok(NULL, ",");

        if (id_str && v1_str && v2_str) {
            int v1 = atoi(v1_str);
            int v2 = atoi(v2_str);
            printf("%s,%d\n", id_str, v1 * v2);
        }
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
