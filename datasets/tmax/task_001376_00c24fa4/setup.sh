#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/source.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <DIRECTION> <TABLE_NAME> <START_ID>\n", argv[0]);
        return 1;
    }

    const char *direction = argv[1];
    const char *table = argv[2];
    int id = atoi(argv[3]);

    if (strcmp(direction, "ANCESTOR") == 0) {
        printf("WITH RECURSIVE dataset_cte AS (\n");
        printf("    SELECT id, parent_id, name FROM %s WHERE id = %d\n", table, id);
        printf("    UNION ALL\n");
        printf("    SELECT t.id, t.parent_id, t.name FROM %s t\n", table);
        printf("    JOIN dataset_cte d ON t.id = d.parent_id\n");
        printf(")\n");
        printf("SELECT * FROM dataset_cte;\n");
    } else if (strcmp(direction, "DESCENDANT") == 0) {
        printf("WITH RECURSIVE dataset_cte AS (\n");
        printf("    SELECT id, parent_id, name FROM %s WHERE id = %d\n", table, id);
        printf("    UNION ALL\n");
        printf("    SELECT t.id, t.parent_id, t.name FROM %s t\n", table);
        printf("    JOIN dataset_cte d ON t.parent_id = d.id\n");
        printf(")\n");
        printf("SELECT * FROM dataset_cte;\n");
    } else {
        fprintf(stderr, "Invalid direction\n");
        return 1;
    }

    return 0;
}
EOF

    gcc -O2 /tmp/source.c -o /app/sql_generator
    strip /app/sql_generator
    rm /tmp/source.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
