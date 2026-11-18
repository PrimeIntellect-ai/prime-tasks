#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/impact_calculator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_EDGES 10000
#define MAX_STR 64

char from[MAX_EDGES][MAX_STR];
char to[MAX_EDGES][MAX_STR];
int edge_count = 0;

int find_longest_path(char* current) {
    int max_depth = 0;
    for (int i = 0; i < edge_count; i++) {
        if (strcmp(from[i], current) == 0) {
            int depth = 1 + find_longest_path(to[i]);
            if (depth > max_depth) {
                max_depth = depth;
            }
        }
    }
    return max_depth;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;

    char line[256];
    char target[MAX_STR] = {0};

    if (fgets(line, sizeof(line), f)) {
        sscanf(line, "TARGET: %s", target);
    }

    while (fgets(line, sizeof(line), f)) {
        char f_node[MAX_STR], t_node[MAX_STR];
        if (sscanf(line, "%s -> %s", f_node, t_node) == 2) {
            strcpy(from[edge_count], f_node);
            strcpy(to[edge_count], t_node);
            edge_count++;
        }
    }
    fclose(f);

    printf("%d\n", find_longest_path(target));
    return 0;
}
EOF

gcc -O2 /app/impact_calculator.c -o /app/impact_calculator
strip /app/impact_calculator
chmod +x /app/impact_calculator

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
