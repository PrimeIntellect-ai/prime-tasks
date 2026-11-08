#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/comments.csv
user_id,thread_id
5001,101
5002,101
5003,101
5001,102
5004,102
5002,103
5005,103
5006,104
5007,104
5006,105
5008,105
5009,105
5006,106
5010,106
EOF

    cat << 'EOF' > /home/user/project_graph.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_ROWS 1000

typedef struct {
    int user_id;
    int thread_id;
} Comment;

int main() {
    FILE *f = fopen("/home/user/data/comments.csv", "r");
    if (!f) return 1;

    char line[256];
    fgets(line, sizeof(line), f); // skip header

    Comment comments[MAX_ROWS];
    int count = 0;

    while (fgets(line, sizeof(line), f)) {
        sscanf(line, "%d,%d", &comments[count].user_id, &comments[count].thread_id);
        count++;
    }
    fclose(f);

    int edges = 0;
    // BUG: Implicit cross join - ignoring thread_id!
    for (int i = 0; i < count; i++) {
        for (int j = i + 1; j < count; j++) {
            if (comments[i].user_id != comments[j].user_id) {
                // TODO: Need an index strategy to map user_ids and store unique edges
                edges++;
            }
        }
    }

    printf("Total edges calculated: %d\n", edges);
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
