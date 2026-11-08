#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest

    mkdir -p /home/user/app

    # Generate observations.csv
    cat << 'EOF' > /home/user/app/setup_data.py
import random
random.seed(42)
with open('/home/user/app/observations.csv', 'w') as f:
    for i in range(2000):
        x = random.uniform(0, 100)
        y = random.uniform(0, 100)
        seq = ''.join(random.choices(['A', 'C', 'G', 'T'], k=150))
        # Make a few nodes have high homology to the primer "ATGCGTACGTTAGC"
        if i in [142, 888, 1024, 1999, 500]:
            seq = "ATGCGTACGTTAGC" + seq[14:]
        f.write(f"{i},{x:.2f},{y:.2f},{seq}\n")
EOF
    python3 /home/user/app/setup_data.py

    # Create mesh_align.c
    cat << 'EOF' > /home/user/app/mesh_align.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define MAX_NODES 2000
#define PRIMER "ATGCGTACGTTAGC"

typedef struct {
    int id;
    double x, y;
    char seq[256];
    int score;
} Node;

Node nodes[MAX_NODES];
int node_count = 0;

// Deliberately slow scoring function
int align_score(const char* target, const char* query) {
    int score = 0;
    // Bottleneck 1: strlen in loop condition (O(N^2) for each sequence)
    // Bottleneck 2: unnecessary inner loop simulating complex graph scoring
    for (size_t i = 0; i < strlen(target); i++) {
        for (size_t j = 0; j < strlen(query); j++) {
            if (target[i] == query[j] && i == j) {
                score += 10;
            }
        }
    }
    return score;
}

void load_data() {
    FILE *f = fopen("/home/user/app/observations.csv", "r");
    if (!f) exit(1);
    while (fscanf(f, "%d,%lf,%lf,%255s", &nodes[node_count].id, &nodes[node_count].x, &nodes[node_count].y, nodes[node_count].seq) == 4) {
        node_count++;
    }
    fclose(f);
}

int main() {
    load_data();

    for (int i = 0; i < node_count; i++) {
        nodes[i].score = align_score(PRIMER, nodes[i].seq);
    }

    // Bottleneck 3: Bubble sort
    for (int i = 0; i < node_count - 1; i++) {
        for (int j = 0; j < node_count - i - 1; j++) {
            if (nodes[j].score < nodes[j+1].score) {
                Node temp = nodes[j];
                nodes[j] = nodes[j+1];
                nodes[j+1] = temp;
            }
        }
    }

    FILE *out = fopen("/home/user/app/top_nodes.txt", "w");
    for (int i = 0; i < 5; i++) {
        fprintf(out, "NodeID: %d, Score: %d\n", nodes[i].id, nodes[i].score);
    }
    fclose(out);

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
