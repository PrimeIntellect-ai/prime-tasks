#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/backup_data

    cat << 'EOF' > /home/user/backup_data/tables.txt
1,100,users
2,100,orders
3,100,products
4,101,users
5,101,orders
6,101,products
7,101,reviews
8,102,users
9,102,orders
EOF

    cat << 'EOF' > /home/user/backup_data/fks.txt
2,1
2,3
5,4
5,6
7,4
7,6
9,8
EOF

    cat << 'EOF' > /home/user/graph_mapper.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int id;
    int backup_id;
    char name[50];
} Table;

typedef struct {
    int source_id;
    int target_id;
} FK;

int main() {
    FILE *ft = fopen("/home/user/backup_data/tables.txt", "r");
    FILE *fk = fopen("/home/user/backup_data/fks.txt", "r");

    if (!ft || !fk) {
        printf("Error opening files.\n");
        return 1;
    }

    Table tables[100];
    int t_count = 0;
    while (fscanf(ft, "%d,%d,%49s", &tables[t_count].id, &tables[t_count].backup_id, tables[t_count].name) == 3) {
        t_count++;
    }

    FK fks[100];
    int fk_count = 0;
    while (fscanf(fk, "%d,%d", &fks[fk_count].source_id, &fks[fk_count].target_id) == 2) {
        fk_count++;
    }

    for (int i = 0; i < t_count; i++) {
        for (int j = 0; j < fk_count; j++) {
            // BUG: Implicit cross join here. The condition to check if fks[j].source_id == tables[i].id is missing.
            printf("(Backup_%d)-[:HAS]->(%s)-[:REFERENCES]->(Table_%d)\n",
                   tables[i].backup_id, tables[i].name, fks[j].target_id);
        }
    }

    fclose(ft);
    fclose(fk);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
