#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc cargo rustc curl
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/hierarchy.csv
parent_id,child_id
1,2
1,3
2,4
2,5
3,6
EOF

    cat << 'EOF' > /home/user/data/values.csv
node_id,value
1,100
2,50
3,100
4,25
5,25
6,150
EOF

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_engine.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NODES 10000

int values[MAX_NODES] = {0};
int has_value[MAX_NODES] = {0};
int parent_arr[MAX_NODES] = {0};
int child_arr[MAX_NODES] = {0};
int edge_count = 0;

int get_sum(int node) {
    int sum = 0;
    if (node >= 0 && node < MAX_NODES && has_value[node]) {
        sum += values[node];
    }
    for (int i = 0; i < edge_count; i++) {
        if (parent_arr[i] == node) {
            sum += get_sum(child_arr[i]);
        }
    }
    return sum;
}

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int target = atoi(argv[1]);

    FILE *f_val = fopen("/home/user/data/values.csv", "r");
    if (f_val) {
        char line[256];
        if (fgets(line, sizeof(line), f_val)) {} // skip header
        while (fgets(line, sizeof(line), f_val)) {
            int n, v;
            if (sscanf(line, "%d,%d", &n, &v) == 2) {
                if (n >= 0 && n < MAX_NODES) {
                    values[n] = v;
                    has_value[n] = 1;
                }
            }
        }
        fclose(f_val);
    }

    FILE *f_hier = fopen("/home/user/data/hierarchy.csv", "r");
    if (f_hier) {
        char line[256];
        if (fgets(line, sizeof(line), f_hier)) {} // skip header
        while (fgets(line, sizeof(line), f_hier)) {
            int p, c;
            if (sscanf(line, "%d,%d", &p, &c) == 2) {
                if (edge_count < MAX_NODES) {
                    parent_arr[edge_count] = p;
                    child_arr[edge_count] = c;
                    edge_count++;
                }
            }
        }
        fclose(f_hier);
    }

    printf("%d\n", get_sum(target));
    return 0;
}
EOF

    gcc -O2 /tmp/legacy_engine.c -o /app/legacy_engine
    strip /app/legacy_engine
    rm /tmp/legacy_engine.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
