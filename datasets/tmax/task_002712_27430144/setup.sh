#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/csv_transformer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int id;
    char name[50];
    int score;
} Record;

Record* db[1000] = {0};

void update_record(int id, const char* name, int score) {
    // BUG: No bounds checking on 'id'. A negative ID or ID >= 1000 will cause a segfault.
    if (!db[id]) {
        db[id] = malloc(sizeof(Record));
    }
    db[id]->id = id;
    strncpy(db[id]->name, name, 49);
    db[id]->score = score;
}

void process_file(const char* filename) {
    FILE *f = fopen(filename, "r");
    if (!f) {
        perror("Failed to open file");
        exit(1);
    }
    char line[256];
    while (fgets(line, sizeof(line), f)) {
        char *line_copy = strdup(line);
        char *id_str = strtok(line_copy, ",");
        char *name = strtok(NULL, ",");
        char *score_str = strtok(NULL, "\n");

        if (id_str && name && score_str) {
            int id = atoi(id_str);
            int score = atoi(score_str);
            update_record(id, name, score);
        }
        free(line_copy);
    }
    fclose(f);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Usage: %s <file.csv>\n", argv[0]);
        return 1;
    }
    process_file(argv[1]);
    return 0;
}
EOF

    mkdir -p /home/user/data
    awk 'BEGIN {
        for(i=1; i<=733; i++) print i ",Customer_" i ",100"
        print "-17,Malicious_User,999"
        for(i=735; i<=1000; i++) print i ",Customer_" i ",100"
    }' > /home/user/data/customer_records.csv

    gcc -g -o /home/user/csv_transformer /home/user/csv_transformer.c

    chmod -R 777 /home/user
